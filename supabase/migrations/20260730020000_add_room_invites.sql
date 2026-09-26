-- The multiplayer tables originally existed only in the hosted database. Keep
-- their baseline here, before this migration's ownership column, so replaying
-- the repository from an empty database is deterministic.

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_id uuid not null,
  status text not null default 'waiting'
    check (status in ('waiting', 'playing', 'finished')),
  numbers integer[],
  round integer not null default 0 check (round >= 0),
  created_at timestamptz not null default now(),
  constraint room_code_format check (code ~ '^[A-HJ-NP-Z2-9]{6}$'),
  constraint room_numbers_are_four check (
    numbers is null or cardinality(numbers) = 4
  ),
  constraint room_numbers_are_in_range check (
    numbers is null or numbers <@ array[1,2,3,4,5,6,7,8,9,10,11,12,13]
  )
);

create table if not exists public.players (
  id uuid primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid default auth.uid() references auth.users(id) on delete cascade,
  display_name text not null,
  score integer not null default 0 check (score >= 0),
  is_host boolean not null default false,
  joined_at timestamptz not null default now(),
  last_ping timestamptz not null default now(),
  ready_round integer not null default 0 check (ready_round >= 0),
  constraint player_display_name_length check (
    char_length(trim(display_name)) between 1 and 30
  )
);

create index if not exists players_room_idx on public.players(room_id, joined_at);
create index if not exists players_user_idx on public.players(user_id);

create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  round integer not null check (round > 0),
  solution text not null,
  submitted_at timestamptz not null default now(),
  constraint one_winner_per_round unique (room_id, round),
  constraint submission_solution_length check (
    char_length(solution) between 1 and 4000
  )
);

create index if not exists submissions_room_idx
  on public.submissions(room_id, round);

alter table public.rooms
  add column if not exists host_user_id uuid
  references auth.users(id) on delete set null;
create index if not exists rooms_host_user_idx
  on public.rooms(host_user_id)
  where host_user_id is not null;

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.submissions enable row level security;

create policy "Signed-in users can read rooms"
  on public.rooms for select to authenticated using (true);
create policy "Signed-in users can create rooms"
  on public.rooms for insert to authenticated
  with check (host_user_id = auth.uid());

create policy "Signed-in users can read players"
  on public.players for select to authenticated using (true);
create policy "Users can create their own player"
  on public.players for insert to authenticated
  with check (user_id = auth.uid());
create policy "Users can update their own player"
  on public.players for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Users can delete their own player"
  on public.players for delete to authenticated
  using (user_id = auth.uid());

create policy "Signed-in users can read submissions"
  on public.submissions for select to authenticated using (true);

revoke all on table public.rooms from anon;
revoke all on table public.players from anon;
revoke all on table public.submissions from anon;
grant select, insert on table public.rooms to authenticated;
grant select, insert, update, delete on table public.players to authenticated;
grant select on table public.submissions to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.rooms;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.players;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.submissions;
exception when duplicate_object then null;
end $$;
