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

## Scheduled data cleanup

The `20260801010000_add_data_retention_jobs.sql` migration enables Supabase Cron
and installs two UTC jobs:

- At 00:05 UTC, daily-puzzle attempts from prior dates are deleted. The solved
  state and both daily leaderboards are derived from this table, so they reset
  together.
- At minute 17 of every hour, rooms that have been finished for at least 24
  hours are deleted along with their players and submissions.

Inspect the jobs after deployment in **Dashboard → Integrations → Cron**, or by
querying `cron.job` in the SQL editor.

## Daily solve friend notifications

After a player completes the daily puzzle, the app invokes the authenticated
`send-friend-notification` Edge Function. The function verifies the current UTC
day’s completion, finds accepted friends, and sends APNs notifications to their
registered devices unless they have already completed that day’s puzzle.
`daily_solve_notifications` prevents duplicate deliveries; its rows are deleted
automatically when the related daily attempt expires.
