# Friends backend

The migrations create anonymous-user profiles, unique usernames, friend requests,
mutual-friend search, row-level security, realtime updates, APNs device-token
storage, and an authenticated owner link for multiplayer rooms. The Edge Function
sends friend-request notifications and host-authorized room invitations.

## Deploy

The Supabase CLI account must have access to project `grliixgrwhzwgmarvmhi`.

```sh
supabase login
supabase link --project-ref grliixgrwhzwgmarvmhi
supabase db push
supabase functions deploy send-friend-notification
```

Enable **Anonymous Sign-Ins** under Authentication → Providers in the Supabase
dashboard.

## Configure APNs

Create an Apple Push Notification authentication key in the Apple Developer
portal and set these Edge Function secrets:

```sh
supabase secrets set \
  APNS_TEAM_ID="YOUR_TEAM_ID" \
  APNS_KEY_ID="YOUR_KEY_ID" \
  APNS_TOPIC="priscillaye.Those-Who-24" \
  APNS_PRIVATE_KEY="$(cat /absolute/path/AuthKey_KEY_ID.p8)"
```

Each registered device token selects the sandbox or production APNs endpoint
automatically. Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY` to deployed functions.
