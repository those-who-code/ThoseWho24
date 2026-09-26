-- Internal ledger for developer-initiated push-notification broadcasts.
-- App clients have no access; only service-role Edge Functions may use it.
create table if not exists public.notification_broadcasts (
  id text primary key,
  title text not null,
  body text not null,
  app_store_url text not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  attempted integer not null default 0,
  delivered integer not null default 0,
  failed integer not null default 0,
  constraint notification_broadcast_id_format
    check (id ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  constraint notification_broadcast_title_length
    check (char_length(title) between 1 and 100),
  constraint notification_broadcast_body_length
    check (char_length(body) between 1 and 500)
);

alter table public.notification_broadcasts enable row level security;
revoke all on table public.notification_broadcasts from anon, authenticated;
