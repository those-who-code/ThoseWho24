alter table public.rooms
  add column if not exists host_user_id uuid
  references auth.users(id) on delete set null;
create index if not exists rooms_host_user_idx
  on public.rooms(host_user_id)
  where host_user_id is not null;
