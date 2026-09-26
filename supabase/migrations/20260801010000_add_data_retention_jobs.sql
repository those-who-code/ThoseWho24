-- Supabase Cron runs scheduled jobs in UTC. Daily puzzle state and leaderboards
-- also use the UTC date, so old attempts can be removed as soon as that date
-- changes.
create extension if not exists pg_cron with schema pg_catalog;
alter table public.rooms
  add column if not exists finished_at timestamptz;
create index if not exists rooms_finished_at_idx
  on public.rooms(finished_at)
  where status = 'finished';
create or replace function public.set_room_finished_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'finished' and old.status is distinct from 'finished' then
    new.finished_at := coalesce(new.finished_at, now());
  elsif new.status is distinct from 'finished' then
    new.finished_at := null;
  end if;

  return new;
end;
$$;
drop trigger if exists set_room_finished_at on public.rooms;
create trigger set_room_finished_at
  before update of status on public.rooms
  for each row execute function public.set_room_finished_at();
-- Start the retention clock for rooms that were already finished before this
-- migration. They will be retained for 24 hours after deployment.
update public.rooms
set finished_at = now()
where status = 'finished'
  and finished_at is null;
create or replace function public.cleanup_expired_game_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Delete children explicitly so this works regardless of the foreign-key
  -- cascade behavior on an older installation of the multiplayer schema.
  delete from public.submissions s
  using public.rooms r
  where s.room_id = r.id
    and r.status = 'finished'
    and r.finished_at <= now() - interval '24 hours';

  delete from public.players p
  using public.rooms r
  where p.room_id = r.id
    and r.status = 'finished'
    and r.finished_at <= now() - interval '24 hours';

  delete from public.rooms r
  where r.status = 'finished'
    and r.finished_at <= now() - interval '24 hours';
end;
$$;
revoke all on function public.set_room_finished_at() from public;
revoke all on function public.cleanup_expired_game_data() from public;
-- Recreating named jobs makes this migration safe to re-run during recovery.
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname in (
      'clear-expired-daily-puzzles',
      'clear-expired-multiplayer-games'
    )
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$$;
-- The leaderboard functions read from daily_puzzle_attempts, so deleting prior
-- dates clears solved state and both leaderboards together. A five-minute delay
-- keeps the job away from the exact date-boundary request spike.
select cron.schedule(
  'clear-expired-daily-puzzles',
  '5 0 * * *',
  $$delete from public.daily_puzzle_attempts
    where puzzle_date < (now() at time zone 'utc')::date$$
);
-- Hourly cleanup means a finished game is removed between 24 and 25 hours
-- after it ends.
select cron.schedule(
  'clear-expired-multiplayer-games',
  '17 * * * *',
  $$select public.cleanup_expired_game_data()$$
);
