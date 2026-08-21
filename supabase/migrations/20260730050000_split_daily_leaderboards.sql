-- Schools compete by their average solve time for the selected UTC day.
create or replace function public.daily_school_averages(p_puzzle_date text default null)
returns table (
  rank bigint,
  school_key text,
  average_milliseconds integer,
  solver_count bigint,
  is_current_school boolean
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
  my_school as (
    select p.university_school_key as school_key
    from public.profiles p
    where p.id = auth.uid()
  ),
  averages as (
    select
      p.university_school_key as school_key,
      round(avg(a.completed_milliseconds))::integer as average_milliseconds,
      count(*) as solver_count
    from public.daily_puzzle_attempts a
    join public.profiles p on p.id = a.user_id
    cross join selected_date d
    where a.puzzle_date = d.puzzle_date
      and a.completed_milliseconds is not null
    group by p.university_school_key
  ),
  ranked as (
    select
      rank() over (order by a.average_milliseconds) as position,
      a.school_key,
      a.average_milliseconds,
      a.solver_count
    from averages a
  )
  select
    r.position,
    r.school_key,
    r.average_milliseconds,
    r.solver_count,
    r.school_key = m.school_key
  from ranked r
  cross join my_school m
  order by r.position, r.school_key
  limit 100;
$$;
-- A user's friend leaderboard contains only that user and accepted friends.
create or replace function public.daily_friends_leaderboard(p_puzzle_date text default null)
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
  friend_group as (
    select auth.uid() as user_id
    union
    select case
      when c.sender_id = auth.uid() then c.receiver_id
      else c.sender_id
    end
    from public.friend_connections c
    where c.status = 'accepted'
      and auth.uid() in (c.sender_id, c.receiver_id)
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
    join friend_group f on f.user_id = a.user_id
    join public.profiles p on p.id = a.user_id
    cross join selected_date d
    where a.puzzle_date = d.puzzle_date
      and a.completed_milliseconds is not null
  )
  select
    r.position,
    r.user_id,
    r.username,
    r.completed_milliseconds,
    r.user_id = auth.uid()
  from ranked r
  order by r.position, r.username
  limit 100;
$$;
revoke all on function public.daily_school_averages(text) from public;
revoke all on function public.daily_friends_leaderboard(text) from public;
grant execute on function public.daily_school_averages(text) to authenticated;
grant execute on function public.daily_friends_leaderboard(text) to authenticated;
