create or replace function public.get_daily_puzzle_status()
returns jsonb
language plpgsql
stable
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

  select * into v_attempt
  from public.daily_puzzle_attempts
  where user_id = auth.uid() and puzzle_date = v_date;

  return jsonb_build_object(
    'puzzle_date', v_date::text,
    'numbers', to_jsonb(public.daily_puzzle_numbers(v_date)),
    'started_at', v_attempt.started_at,
    'completed_milliseconds', v_attempt.completed_milliseconds
  );
end;
$$;
revoke all on function public.get_daily_puzzle_status() from public;
grant execute on function public.get_daily_puzzle_status() to authenticated;
