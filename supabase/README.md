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

## Sign in with Apple and account migration

Before releasing the Apple-account migration:

1. Enable the **Apple** provider in Supabase Authentication → Providers and add
   `priscillaye.Those-Who-24` as an allowed client ID.
2. Enable **Manual identity linking**. Existing anonymous accounts use native
   Apple ID-token linking so their current UUID, username, and friends remain
   intact.
3. Enable **Sign in with Apple** for the App ID in the Apple Developer portal
   and refresh the provisioning profiles. The Xcode capability and entitlement
   are already present in this repository.
4. Confirm the hosted Auth service includes the Apple ID-token security fix
   from Supabase Auth 2.185.0 or newer.
5. Apply `20260820010000_apple_accounts_and_recovery.sql`. It snapshots the
   current `@priscillaye` UUID into `recovery_admins`; admin authorization uses
   that server-side UUID, never the editable username.

New users authenticate with Apple before choosing a username. Existing users
with a username link Apple in place. Recovery requests and approvals remain
inside the app; approved recovery atomically moves the old username, friend
graph, university, devices, and permanent daily completion dates to the
requester's Apple-backed account.

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
