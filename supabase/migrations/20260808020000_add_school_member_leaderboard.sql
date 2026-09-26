-- Return every completed daily solve for a selected university so users can
-- drill into a school average and see its individual standings.
create or replace function public.daily_school_members_leaderboard(
  p_school_key text,
  p_puzzle_date text default null
)
returns table (
  rank bigint,
  user_id uuid,
  username text,
  completed_milliseconds integer,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with selected_date as (
    select coalesce(
      nullif(p_puzzle_date, '')::date,
      (now() at time zone 'utc')::date
    ) as puzzle_date
  ),
  ranked as (
    select
      rank() over (
        order by a.completed_milliseconds, a.completed_at
      ) as position,
      a.user_id,
      coalesce(p.username::text, 'player') as username,
      a.completed_milliseconds
    from public.daily_puzzle_attempts a
    join public.profiles p on p.id = a.user_id
    cross join selected_date d
    where a.puzzle_date = d.puzzle_date
      and a.completed_milliseconds is not null
      and p.university_school_key = p_school_key
  )
  select
    r.position,
    r.user_id,
    r.username,
    r.completed_milliseconds,
    r.user_id = auth.uid()
  from ranked r
  where auth.uid() is not null
  order by r.position, r.username;
$$;

revoke all on function public.daily_school_members_leaderboard(text, text) from public;
grant execute on function public.daily_school_members_leaderboard(text, text) to authenticated;
