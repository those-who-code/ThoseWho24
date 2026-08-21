alter table public.profiles
  add column if not exists university_email text,
  add column if not exists university_school_key text not null default 'non-school',
  add column if not exists university_verified boolean not null default false;
create table if not exists public.daily_puzzle_attempts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  puzzle_date date not null,
  numbers integer[] not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_milliseconds integer,
  primary key (user_id, puzzle_date),
  constraint daily_numbers_are_four check (cardinality(numbers) = 4),
  constraint daily_time_is_positive check (
    completed_milliseconds is null or completed_milliseconds >= 0
  )
);
create index if not exists daily_puzzle_ranking_idx
  on public.daily_puzzle_attempts(puzzle_date, completed_milliseconds)
  where completed_milliseconds is not null;
alter table public.daily_puzzle_attempts enable row level security;
-- Daily puzzles come from a stable, solvable bank. Indexing by the UTC date makes
-- the selection identical across devices without trusting a device clock.
create or replace function public.daily_puzzle_numbers(p_date date)
returns integer[]
language sql
immutable
set search_path = ''
as $$
  select case mod((p_date - date '2026-01-01'), 14)
    when 0 then array[1,2,3,4]
    when 1 then array[3,3,8,8]
    when 2 then array[5,5,5,1]
    when 3 then array[2,3,4,6]
    when 4 then array[1,3,4,6]
    when 5 then array[2,3,4,5]
    when 6 then array[2,5,7,9]
    when 7 then array[3,5,7,11]
    when 8 then array[4,5,6,7]
    when 9 then array[2,6,8,12]
    when 10 then array[1,7,10,13]
    when 11 then array[3,4,8,9]
    when 12 then array[2,4,9,13]
    else array[5,6,7,8]
  end;
$$;
create or replace function public.start_daily_puzzle()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date := (now() at time zone 'utc')::date;
  v_attempt public.daily_puzzle_attempts;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.daily_puzzle_attempts (user_id, puzzle_date, numbers)
  values (auth.uid(), v_date, public.daily_puzzle_numbers(v_date))
  on conflict (user_id, puzzle_date) do nothing;

  select * into v_attempt
  from public.daily_puzzle_attempts
  where user_id = auth.uid() and puzzle_date = v_date;

  return jsonb_build_object(
    'puzzle_date', v_attempt.puzzle_date::text,
    'numbers', to_jsonb(v_attempt.numbers),
    'started_at', v_attempt.started_at,
    'completed_milliseconds', v_attempt.completed_milliseconds
  );
end;
$$;
create or replace function public.submit_daily_puzzle(p_puzzle_date text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date;
  v_milliseconds integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  begin
    v_date := p_puzzle_date::date;
  exception when others then
    raise exception 'Invalid puzzle date';
  end;

  if v_date <> (now() at time zone 'utc')::date then
    raise exception 'That daily puzzle has ended';
  end if;

  update public.daily_puzzle_attempts
  set
    completed_at = coalesce(completed_at, now()),
    completed_milliseconds = coalesce(
      completed_milliseconds,
      greatest(0, floor(extract(epoch from (now() - started_at)) * 1000)::integer)
    )
  where user_id = auth.uid()
    and puzzle_date = v_date
  returning completed_milliseconds into v_milliseconds;

  if v_milliseconds is null then
    raise exception 'Start the daily puzzle before submitting';
  end if;
  return v_milliseconds;
end;
$$;
create or replace function public.get_university_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'email', p.university_email,
    'school_key', p.university_school_key,
    'is_verified', p.university_verified
  )
  from public.profiles p
  where p.id = auth.uid();
$$;
create or replace function public.sync_university_email()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_domain text;
  v_status jsonb;
begin
  select lower(u.email)
  into v_email
  from auth.users u
  where u.id = auth.uid()
    and u.email_confirmed_at is not null;

  if v_email is null then
    raise exception 'Verify your email before joining a university';
  end if;

  v_domain := split_part(v_email, '@', 2);
  if not (
    v_domain ~ '\.edu$'
    or v_domain ~ '\.ac\.[a-z]{2}$'
    or v_domain ~ '\.edu\.[a-z]{2}$'
  ) then
    raise exception 'That is not a supported university email domain';
  end if;

  update public.profiles
  set
    university_email = v_email,
    university_school_key = v_domain,
    university_verified = true,
    updated_at = now()
  where id = auth.uid();

  v_status := public.get_university_status();
  return v_status;
end;
$$;
create or replace function public.daily_school_leaderboard(p_puzzle_date text default null)
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
  with me as (
    select p.university_school_key as school_key
    from public.profiles p
    where p.id = auth.uid()
  ),
  ranked as (
    select
      rank() over (
        order by a.completed_milliseconds asc, a.completed_at asc
      ) as position,
      a.user_id,
      coalesce(p.username::text, 'player') as username,
      a.completed_milliseconds
    from public.daily_puzzle_attempts a
    join public.profiles p on p.id = a.user_id
    cross join me
    where a.puzzle_date = coalesce(
      nullif(p_puzzle_date, '')::date,
      (now() at time zone 'utc')::date
    )
      and a.completed_milliseconds is not null
      and p.university_school_key = me.school_key
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
revoke all on function public.daily_puzzle_numbers(date) from public;
revoke all on function public.start_daily_puzzle() from public;
revoke all on function public.submit_daily_puzzle(text) from public;
revoke all on function public.get_university_status() from public;
revoke all on function public.sync_university_email() from public;
revoke all on function public.daily_school_leaderboard(text) from public;
grant execute on function public.start_daily_puzzle() to authenticated;
grant execute on function public.submit_daily_puzzle(text) to authenticated;
grant execute on function public.get_university_status() to authenticated;
grant execute on function public.sync_university_email() to authenticated;
grant execute on function public.daily_school_leaderboard(text) to authenticated;
