-- Historical migration: this was applied remotely before the client-side timer
-- change was reverted. Keep it so local migration history matches production.
drop function if exists public.submit_daily_puzzle(text);

create function public.submit_daily_puzzle(
  p_puzzle_date text,
  p_elapsed_milliseconds integer
)
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

  if p_elapsed_milliseconds < 0 or p_elapsed_milliseconds > 86400000 then
    raise exception 'Invalid solve time';
  end if;

  update public.daily_puzzle_attempts
  set
    completed_at = coalesce(completed_at, now()),
    completed_milliseconds = coalesce(completed_milliseconds, p_elapsed_milliseconds)
  where user_id = auth.uid()
    and puzzle_date = v_date
  returning completed_milliseconds into v_milliseconds;

  if v_milliseconds is null then
    raise exception 'Start the daily puzzle before submitting';
  end if;
  return v_milliseconds;
end;
$$;

revoke all on function public.submit_daily_puzzle(text, integer) from public;
grant execute on function public.submit_daily_puzzle(text, integer) to authenticated;
