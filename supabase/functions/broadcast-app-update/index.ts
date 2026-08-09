import { createClient } from "npm:@supabase/supabase-js@2";

interface BroadcastRequest {
  title?: string;
  body?: string;
  app_store_url?: string;
  broadcast_id?: string;
}

interface DeviceToken {
  id: string;
  token: string;
}

interface APNsResult {
  delivered: boolean;
  invalidToken: boolean;
  error?: string;
}

const batchSize = 50;
const pageSize = 500;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const suppliedSecret = request.headers.get("x-broadcast-secret");
    const expectedSecret = requiredEnv("BROADCAST_SECRET");
    if (!suppliedSecret || suppliedSecret !== expectedSecret) {
      return json({ error: "Unauthorized" }, 401);
    }

    const payload = await request.json() as BroadcastRequest;
    const validationError = validate(payload);
    if (validationError) return json({ error: validationError }, 400);

    const title = payload.title!.trim();
    const body = payload.body!.trim();
    const appStoreURL = payload.app_store_url!;
    const broadcastId = payload.broadcast_id!;

    const adminClient = createClient(
      requiredEnv("SUPABASE_URL"),
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    );

    // The unique broadcast ID makes an accidental repeated invocation safe.
    const { error: claimError } = await adminClient
      .from("notification_broadcasts")
      .insert({
        id: broadcastId,
        title,
        body,
        app_store_url: appStoreURL,
      });
    if (claimError) {
      if (claimError.code === "23505") {
        return json({ error: "This broadcast_id has already been used" }, 409);
      }
      throw claimError;
    }

    const apnsJWT = await makeAPNsJWT();
    let attempted = 0;
    let delivered = 0;
    let failed = 0;
    let removedInvalidTokens = 0;
    let lastDeviceId: string | null = null;

    while (true) {
      let query = adminClient
        .from("device_tokens")
        .select("id,token")
        .eq("environment", "production")
        .order("id")
        .limit(pageSize);
      if (lastDeviceId) query = query.gt("id", lastDeviceId);
      const { data, error } = await query;
      if (error) throw error;

      const devices = (data ?? []) as DeviceToken[];
      if (devices.length === 0) break;

      for (let index = 0; index < devices.length; index += batchSize) {
        const batch = devices.slice(index, index + batchSize);
        const results = await Promise.all(batch.map(async (device) => ({
          device,
          result: await sendAPNs(
            device.token,
            apnsJWT,
            title,
            body,
            appStoreURL,
            broadcastId,
          ),
        })));

        attempted += results.length;
        delivered += results.filter(({ result }) => result.delivered).length;
        failed += results.filter(({ result }) => !result.delivered).length;

        const invalidIds = results
          .filter(({ result }) => result.invalidToken)
          .map(({ device }) => device.id);
        if (invalidIds.length > 0) {
          const { error: deleteError } = await adminClient
            .from("device_tokens")
            .delete()
            .in("id", invalidIds);
          if (deleteError) throw deleteError;
          removedInvalidTokens += invalidIds.length;
        }
      }

      if (devices.length < pageSize) break;
      lastDeviceId = devices[devices.length - 1].id;
    }

    const { error: completionError } = await adminClient
      .from("notification_broadcasts")
      .update({
        completed_at: new Date().toISOString(),
        attempted,
        delivered,
        failed,
      })
      .eq("id", broadcastId);
    if (completionError) throw completionError;

    return json({
      broadcast_id: broadcastId,
      attempted,
      delivered,
      failed,
      removed_invalid_tokens: removedInvalidTokens,
    });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      500,
    );
  }
});

function validate(payload: BroadcastRequest) {
  if (!payload.title?.trim() || payload.title.trim().length > 100) {
    return "title must contain 1-100 characters";
  }
  if (!payload.body?.trim() || payload.body.trim().length > 500) {
    return "body must contain 1-500 characters";
  }
  if (!payload.broadcast_id || !/^[a-z0-9][a-z0-9._-]{0,63}$/.test(payload.broadcast_id)) {
    return "broadcast_id has an invalid format";
  }
  try {
    const url = new URL(payload.app_store_url ?? "");
    if (url.protocol !== "https:" || url.hostname !== "apps.apple.com") {
      return "app_store_url must be an https://apps.apple.com URL";
    }
  } catch {
    return "app_store_url is invalid";
  }
  return null;
}

async function sendAPNs(
  deviceToken: string,
  jwt: string,
  title: string,
  body: string,
  appStoreURL: string,
  broadcastId: string,
): Promise<APNsResult> {
  const response = await fetch(`https://api.push.apple.com/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": requiredEnv("APNS_TOPIC"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 24 * 60 * 60),
      "apns-collapse-id": broadcastId,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: { title, body },
        sound: "default",
      },
      notification_type: "app_update",
      app_store_url: appStoreURL,
      broadcast_id: broadcastId,
    }),
  });

  if (response.ok) return { delivered: true, invalidToken: false };

  const responseBody = await response.text();
  let reason = responseBody;
  try {
    reason = (JSON.parse(responseBody) as { reason?: string }).reason ?? responseBody;
  } catch {
    // Preserve the raw APNs response when it is not JSON.
  }
  return {
    delivered: false,
    invalidToken: response.status === 410 || reason === "BadDeviceToken",
    error: `APNs ${response.status}: ${reason}`,
  };
}

async function makeAPNsJWT() {
  const header = base64Url(new TextEncoder().encode(JSON.stringify({
    alg: "ES256",
    kid: requiredEnv("APNS_KEY_ID"),
  })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: requiredEnv("APNS_TEAM_ID"),
    iat: Math.floor(Date.now() / 1000),
  })));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(requiredEnv("APNS_PRIVATE_KEY")),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function pemToBytes(pem: string) {
  const base64 = pem.replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
