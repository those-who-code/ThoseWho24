-- High-severity integrity and liveness fixes. Daily and multiplayer wins now
-- require a complete, mathematically valid three-move proof. Multiplayer
-- heartbeats also dissolve rooms whose host disappeared without signing out.

alter table public.daily_puzzle_attempts
  add column if not exists solution text;

alter table public.daily_puzzle_attempts
  drop constraint if exists daily_solution_length;
alter table public.daily_puzzle_attempts
  add constraint daily_solution_length check (
    solution is null or char_length(solution) between 1 and 4000
  );

create or replace function public.is_valid_24_solution(
  p_numbers integer[],
  p_solution text
)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
  v_encoded text;
  v_tokens text[];
  v_parts text[];
  v_numerators numeric[] := array[0, 0, 0, 0]::numeric[];
  v_denominators numeric[] := array[1, 1, 1, 1]::numeric[];
  v_visible boolean[] := array[true, true, true, true];
  v_first integer;
  v_second integer;
  v_op text;
  v_result_numerator numeric;
  v_result_denominator numeric;
  v_claimed_numerator numeric;
  v_claimed_denominator numeric;
  v_result_parts text[];
  v_remaining integer := 0;
  v_final_index integer;
begin
  if cardinality(p_numbers) <> 4
     or not (p_numbers <@ array[1,2,3,4,5,6,7,8,9,10,11,12,13])
     or char_length(p_solution) > 4000 then
    return false;
  end if;

  for i in 1..4 loop
    v_numerators[i] := p_numbers[i];
  end loop;

  -- Multiplayer prepends a human-readable display followed by "|". Daily
  -- submissions contain only the canonical index moves.
  v_encoded := case
    when position('|' in p_solution) > 0 then split_part(p_solution, '|', 2)
    else p_solution
  end;
  v_tokens := string_to_array(v_encoded, ',');
  if cardinality(v_tokens) <> 3 then return false; end if;

  for i in 1..3 loop
    v_parts := string_to_array(v_tokens[i], ':');
    if cardinality(v_parts) <> 4
       or v_parts[1] !~ '^[0-3]$'
       or v_parts[2] !~ '^[0-3]$' then
      return false;
    end if;

    v_first := v_parts[1]::integer + 1;
    v_second := v_parts[2]::integer + 1;
    v_op := v_parts[3];
    if v_first = v_second or not v_visible[v_first] or not v_visible[v_second] then
      return false;
    end if;

    case v_op
      when '+' then
        v_result_numerator :=
          v_numerators[v_first] * v_denominators[v_second]
          + v_numerators[v_second] * v_denominators[v_first];
        v_result_denominator := v_denominators[v_first] * v_denominators[v_second];
      when '−' then
        v_result_numerator :=
          v_numerators[v_first] * v_denominators[v_second]
          - v_numerators[v_second] * v_denominators[v_first];
        v_result_denominator := v_denominators[v_first] * v_denominators[v_second];
      when '×' then
        v_result_numerator := v_numerators[v_first] * v_numerators[v_second];
        v_result_denominator := v_denominators[v_first] * v_denominators[v_second];
      when '÷' then
        if v_numerators[v_second] = 0 then return false; end if;
        v_result_numerator := v_numerators[v_first] * v_denominators[v_second];
        v_result_denominator := v_denominators[v_first] * v_numerators[v_second];
      else
        return false;
    end case;

    if v_result_denominator < 0 then
      v_result_numerator := -v_result_numerator;
      v_result_denominator := -v_result_denominator;
    end if;

    if char_length(v_parts[4]) > 64
       or v_parts[4] !~ '^-?[0-9]+(/[1-9][0-9]*)?$' then
      return false;
    end if;
    v_result_parts := string_to_array(v_parts[4], '/');
    v_claimed_numerator := v_result_parts[1]::numeric;
    v_claimed_denominator := case
      when cardinality(v_result_parts) = 2 then v_result_parts[2]::numeric
      else 1
    end;
    if v_claimed_numerator * v_result_denominator
       <> v_result_numerator * v_claimed_denominator then
      return false;
    end if;

    v_visible[v_first] := false;
    v_numerators[v_second] := v_result_numerator;
    v_denominators[v_second] := v_result_denominator;
  end loop;

  for i in 1..4 loop
    if v_visible[i] then
      v_remaining := v_remaining + 1;
      v_final_index := i;
    end if;
  end loop;
  return v_remaining = 1
    and v_numerators[v_final_index] = 24 * v_denominators[v_final_index];
exception when others then
  return false;
end;
$$;

-- The old one-argument endpoint accepted an unproven win. Removing it makes
-- old clients fail closed instead of allowing forged leaderboard entries.
revoke all on function public.submit_daily_puzzle(text) from public;
drop function public.submit_daily_puzzle(text);

create function public.submit_daily_puzzle(
  p_puzzle_date text,
  p_solution text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_date date;
  v_attempt public.daily_puzzle_attempts;
  v_milliseconds integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  begin
    v_date := p_puzzle_date::date;
  exception when others then
    raise exception 'Invalid puzzle date';
  end;
  if v_date <> (now() at time zone 'utc')::date then
    raise exception 'That daily puzzle has ended';
  end if;

  select * into v_attempt
  from public.daily_puzzle_attempts
  where user_id = auth.uid() and puzzle_date = v_date
  for update;
  if v_attempt.user_id is null then
    raise exception 'Start the daily puzzle before submitting';
  end if;
  if v_attempt.completed_milliseconds is not null then
    return v_attempt.completed_milliseconds;
  end if;
  if p_solution is null
     or not coalesce(public.is_valid_24_solution(v_attempt.numbers, p_solution), false) then
    raise exception 'The submitted moves do not solve this puzzle';
  end if;

  v_milliseconds := greatest(
    0,
    floor(extract(epoch from (now() - v_attempt.started_at)) * 1000)::integer
  );
  update public.daily_puzzle_attempts
  set completed_at = now(),
      completed_milliseconds = v_milliseconds,
      solution = p_solution
  where user_id = auth.uid() and puzzle_date = v_date;

  insert into public.daily_completions (user_id, puzzle_date)
  values (auth.uid(), v_date)
  on conflict do nothing;
  return v_milliseconds;
end;
$$;

-- Completion history is server-authored by accepted solves and recovery. A
-- client cannot prove that an arbitrary local date represents a real solve.
revoke all on function public.merge_daily_completion_dates(text[]) from public;
drop function public.merge_daily_completion_dates(text[]);

create or replace function public.claim_round_win(
  p_room_id uuid,
  p_player_id uuid,
  p_round integer,
  p_solution text
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_room public.rooms;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_solution is null or nullif(trim(p_solution), '') is null
     or char_length(p_solution) > 4000 then
    raise exception 'Invalid solution';
  end if;
  select * into v_room from public.rooms
  where id = p_room_id for update;
  if v_room.id is null or v_room.status <> 'playing' or v_room.round <> p_round then
    return false;
  end if;
  if not exists (
    select 1 from public.players p
    where p.id = p_player_id and p.room_id = p_room_id
      and p.user_id = auth.uid()
  ) then
    raise exception 'Player is not authorized for this room';
  end if;
  if not coalesce(public.is_valid_24_solution(v_room.numbers, p_solution), false) then
    raise exception 'The submitted moves do not solve this puzzle';
  end if;
  if exists (
    select 1 from public.submissions s
    where s.room_id = p_room_id and s.round = p_round
  ) then
    return false;
  end if;
  insert into public.submissions (room_id, player_id, round, solution)
  values (p_room_id, p_player_id, p_round, p_solution);
  update public.players set score = score + 1 where id = p_player_id;
  return true;
exception when unique_violation then
  return false;
end;
$$;

create or replace function public.heartbeat_room_player(
  p_player_id uuid,
  p_room_id uuid
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.players
  set last_ping = now()
  where id = p_player_id and room_id = p_room_id and user_id = auth.uid();
  if not found then raise exception 'Player is not authorized for this room'; end if;

  -- A connected guest can close an abandoned room promptly. A healthy host
  -- refreshes every 15 seconds, leaving generous tolerance for jitter.
  update public.rooms r
  set status = 'finished'
  where r.id = p_room_id
    and r.status <> 'finished'
    and r.host_id <> p_player_id
    and not exists (
      select 1 from public.players host
      where host.id = r.host_id and host.room_id = r.id
        and host.last_ping >= now() - interval '45 seconds'
    );
end;
$$;

-- The scheduled sweep handles empty abandoned rooms even when no guest remains
-- to send a heartbeat. The existing trigger supplies finished_at.
create or replace function public.cleanup_expired_game_data()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.rooms r
  set status = 'finished'
  where r.status <> 'finished'
    and not exists (
      select 1 from public.players host
      where host.id = r.host_id and host.room_id = r.id
        and host.last_ping >= now() - interval '2 minutes'
    );

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

do $$
declare v_job_id bigint;
begin
  for v_job_id in
    select jobid from cron.job where jobname = 'clear-expired-multiplayer-games'
  loop
    perform cron.unschedule(v_job_id);
  end loop;
end;
$$;
select cron.schedule(
  'clear-expired-multiplayer-games',
  '*/5 * * * *',
  $$select public.cleanup_expired_game_data()$$
);

revoke all on function public.is_valid_24_solution(integer[], text) from public;
revoke all on function public.submit_daily_puzzle(text, text) from public;
revoke all on function public.claim_round_win(uuid, uuid, integer, text) from public;
revoke all on function public.heartbeat_room_player(uuid, uuid) from public;
revoke all on function public.cleanup_expired_game_data() from public;
grant execute on function public.submit_daily_puzzle(text, text) to authenticated;
grant execute on function public.claim_round_win(uuid, uuid, integer, text) to authenticated;
grant execute on function public.heartbeat_room_player(uuid, uuid) to authenticated;
