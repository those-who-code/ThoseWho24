import { createClient } from "npm:@supabase/supabase-js@2";

type NotificationKind =
  | "request_received"
  | "request_accepted"
  | "room_invite"
  | "daily_puzzle_solved";

interface NotificationRequest {
  request_id?: string;
  kind?: NotificationKind;
  recipient_id?: string;
  room_code?: string;
}

interface NotificationPayload {
  friend_event: NotificationKind;
  request_id?: string;
  room_code?: string;
  daily_puzzle?: boolean;
}

interface DeviceToken {
  user_id?: string;
  token: string;
  environment: "development" | "production";
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) {
      return json({ error: "Missing authorization" }, 401);
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const callerClient = createClient(
      supabaseUrl,
      requiredEnv("SUPABASE_ANON_KEY"),
      { global: { headers: { Authorization: authorization } } },
    );
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { data: authData, error: authError } = await callerClient.auth.getUser();
    if (authError || !authData.user) {
      return json({ error: "Invalid session" }, 401);
    }

    const body = await request.json() as NotificationRequest;
    const callerId = authData.user.id;

    if (body.kind === "daily_puzzle_solved") {
      return await notifyFriendsOfDailySolve(adminClient, callerId);
    }

    let recipientId: string;
    let title: string;
    let message: string;
    let payload: NotificationPayload;

    if (body.recipient_id || body.room_code) {
      if (
        !isUUID(body.recipient_id) ||
        !body.room_code ||
        !/^[A-HJ-NP-Z2-9]{6}$/.test(body.room_code)
      ) {
        return json({ error: "Invalid room invitation" }, 400);
      }

      const roomCode = body.room_code.toUpperCase();
      const [{ data: room }, { data: friendship }] = await Promise.all([
        adminClient.from("rooms")
          .select("code,status,host_user_id")
          .eq("code", roomCode)
          .eq("status", "waiting")
          .maybeSingle(),
        adminClient.from("friend_connections")
          .select("id")
          .eq("status", "accepted")
          .or(
            `and(sender_id.eq.${callerId},receiver_id.eq.${body.recipient_id}),` +
              `and(sender_id.eq.${body.recipient_id},receiver_id.eq.${callerId})`,
          )
          .maybeSingle(),
      ]);

      if (!room) {
        return json({ error: "Waiting room not found" }, 404);
      }
      if (room.host_user_id !== callerId) {
        return json({ error: "Only the room host can invite friends" }, 403);
      }
      if (!friendship) {
        return json({ error: "Recipient is not an accepted friend" }, 403);
      }

      recipientId = body.recipient_id;
      title = "Game invite";
      message = `invited you to room ${roomCode}. Tap to join!`;
      payload = { friend_event: "room_invite", room_code: roomCode };
    } else {
      if (
        !body.request_id ||
        !body.kind ||
        !["request_received", "request_accepted"].includes(body.kind)
      ) {
        return json({ error: "Invalid notification request" }, 400);
      }

      const { data: connection, error: connectionError } = await adminClient
        .from("friend_connections")
        .select("id,sender_id,receiver_id,status")
        .eq("id", body.request_id)
        .single();
      if (connectionError || !connection) {
        return json({ error: "Friend request not found" }, 404);
      }

      if (
        body.kind === "request_received" &&
        connection.sender_id === callerId &&
        connection.status === "pending"
      ) {
        recipientId = connection.receiver_id;
      } else if (
        body.kind === "request_accepted" &&
        connection.receiver_id === callerId &&
        connection.status === "accepted"
      ) {
        recipientId = connection.sender_id;
      } else {
        return json({ error: "Notification does not match this request" }, 403);
      }

      title = body.kind === "request_received"
        ? "New friend request"
        : "Friend request accepted";
      message = body.kind === "request_received"
        ? "wants to be friends."
        : "accepted your friend request.";
      payload = {
        friend_event: body.kind,
        request_id: body.request_id,
      };
    }

    const [{ data: profile }, { data: tokens, error: tokenError }] =
      await Promise.all([
        adminClient.from("profiles").select("username").eq("id", callerId).single(),
        adminClient.from("device_tokens")
          .select("token,environment")
          .eq("user_id", recipientId),
      ]);
    if (tokenError) throw tokenError;

    const username = profile?.username ?? "Someone";
    message = `@${username} ${message}`;

    const results = await Promise.allSettled(
      ((tokens ?? []) as DeviceToken[]).map((device) =>
        sendAPNs(device, title, message, payload)
      ),
    );

    const delivered = results.filter((result) => result.status === "fulfilled").length;
    if (payload.friend_event === "room_invite" && delivered === 0) {
      const error = results.length === 0
        ? "This friend does not have push notifications registered"
        : "The room invitation could not be delivered";
      return json({ error, delivered, attempted: results.length }, 424);
    }
    return json({ delivered, attempted: results.length });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      500,
    );
  }
});

async function notifyFriendsOfDailySolve(
  adminClient: ReturnType<typeof createClient>,
  solverId: string,
) {
  const puzzleDate = new Date().toISOString().slice(0, 10);
  const { data: attempt, error: attemptError } = await adminClient
    .from("daily_puzzle_attempts")
    .select("user_id")
    .eq("user_id", solverId)
    .eq("puzzle_date", puzzleDate)
    .not("completed_milliseconds", "is", null)
    .maybeSingle();

  if (attemptError) throw attemptError;
  if (!attempt) {
    return json({ error: "Complete today's daily puzzle first" }, 403);
  }

  const { data: connections, error: connectionsError } = await adminClient
    .from("friend_connections")
    .select("sender_id,receiver_id")
    .eq("status", "accepted")
    .or(`sender_id.eq.${solverId},receiver_id.eq.${solverId}`);
  if (connectionsError) throw connectionsError;

  const friendIds = [...new Set((connections ?? []).map((connection) =>
    connection.sender_id === solverId
      ? connection.receiver_id
      : connection.sender_id
  ))];
  if (friendIds.length === 0) {
    return json({ delivered: 0, attempted: 0, recipients: 0 });
  }

  // A friend who already finished today's puzzle does not need a prompt to
  // play it. This also handles completion on another device before delivery.
  const { data: completedFriends, error: completedFriendsError } = await adminClient
    .from("daily_puzzle_attempts")
    .select("user_id")
    .in("user_id", friendIds)
    .eq("puzzle_date", puzzleDate)
    .not("completed_milliseconds", "is", null);
  if (completedFriendsError) throw completedFriendsError;

  const completedFriendIds = new Set(
    (completedFriends ?? []).map((attempt) => attempt.user_id as string),
  );
  const eligibleFriendIds = friendIds.filter((friendId) =>
    !completedFriendIds.has(friendId)
  );
  if (eligibleFriendIds.length === 0) {
    return json({ delivered: 0, attempted: 0, recipients: 0 });
  }

  // ignoreDuplicates makes retries safe. With return=representation, PostgREST
  // returns only rows claimed by this invocation, so concurrent requests do not
  // send the same solve notification twice.
  const claims = eligibleFriendIds.map((recipientId) => ({
    solver_id: solverId,
    recipient_id: recipientId,
    puzzle_date: puzzleDate,
  }));
  const { data: claimed, error: claimError } = await adminClient
    .from("daily_solve_notifications")
    .upsert(claims, {
      onConflict: "solver_id,recipient_id,puzzle_date",
      ignoreDuplicates: true,
    })
    .select("recipient_id");
  if (claimError) throw claimError;

  const recipientIds = [...new Set(
    (claimed ?? []).map((claim) => claim.recipient_id as string),
  )];
  if (recipientIds.length === 0) {
    return json({ delivered: 0, attempted: 0, recipients: 0 });
  }

  const [{ data: profile }, { data: tokens, error: tokenError }] =
    await Promise.all([
      adminClient.from("profiles").select("username").eq("id", solverId).single(),
      adminClient.from("device_tokens")
        .select("user_id,token,environment")
        .in("user_id", recipientIds),
    ]);
  if (tokenError) throw tokenError;

  const username = profile?.username ?? "Someone";
  const payload: NotificationPayload = {
    friend_event: "daily_puzzle_solved",
    daily_puzzle: true,
  };
  const results = await Promise.allSettled(
    ((tokens ?? []) as DeviceToken[]).map((device) =>
      sendAPNs(
        device,
        "A friend made 24!",
        `@${username} solved today's daily puzzle. Can you?`,
        payload,
      )
    ),
  );

  return json({
    delivered: results.filter((result) => result.status === "fulfilled").length,
    attempted: results.length,
    recipients: recipientIds.length,
  });
}

async function sendAPNs(
  device: DeviceToken,
  title: string,
  body: string,
  data: NotificationPayload,
) {
  const jwt = await makeAPNsJWT();
  const host = device.environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
  const response = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": requiredEnv("APNS_TOPIC"),
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: {
        alert: { title, body },
        sound: "default",
        badge: 1,
      },
      ...data,
    }),
  });
  if (!response.ok) {
    throw new Error(`APNs ${response.status}: ${await response.text()}`);
  }
}

async function makeAPNsJWT() {
  const header = base64Url(
    new TextEncoder().encode(JSON.stringify({
      alg: "ES256",
      kid: requiredEnv("APNS_KEY_ID"),
    })),
  );
  const claims = base64Url(
    new TextEncoder().encode(JSON.stringify({
      iss: requiredEnv("APNS_TEAM_ID"),
      iat: Math.floor(Date.now() / 1000),
    })),
  );
  const signingInput = `${header}.${claims}`;
  const keyData = pemToBytes(requiredEnv("APNS_PRIVATE_KEY"));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
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
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
