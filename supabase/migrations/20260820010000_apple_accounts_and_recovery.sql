-- Permanent daily completion history plus Apple-backed account recovery.
-- Existing anonymous users keep their auth UUID when they link Apple. Users
-- who already lost a session recover by atomically moving the old account data
-- to their new Apple-authenticated UUID.

create table if not exists public.daily_completions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  puzzle_date date not null,
  completed_at timestamptz not null default now(),
  primary key (user_id, puzzle_date)
);

alter table public.daily_completions enable row level security;

drop policy if exists "Users can read their daily completions" on public.daily_completions;
create policy "Users can read their daily completions"
  on public.daily_completions for select to authenticated
  using (user_id = auth.uid());

insert into public.daily_completions (user_id, puzzle_date, completed_at)
select user_id, puzzle_date, coalesce(completed_at, now())
from public.daily_puzzle_attempts
where completed_milliseconds is not null
on conflict do nothing;

create or replace function public.list_daily_completion_dates()
returns table (puzzle_date text)
language sql stable security definer set search_path = ''
as $$
  select d.puzzle_date::text
  from public.daily_completions d
  where d.user_id = auth.uid()
  order by d.puzzle_date;
$$;

create or replace function public.merge_daily_completion_dates(p_dates text[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_value text;
  v_date date;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  foreach v_value in array coalesce(p_dates, array[]::text[]) loop
    begin
      v_date := v_value::date;
    exception when others then
      raise exception 'Invalid completion date';
    end;
    if v_date < date '2026-01-01' or v_date > (now() at time zone 'utc')::date then
      raise exception 'Completion date is outside the allowed range';
    end if;
    insert into public.daily_completions (user_id, puzzle_date)
    values (auth.uid(), v_date)
    on conflict do nothing;
  end loop;
end;
$$;

-- Preserve a permanent date ledger whenever the server accepts a daily solve.
create or replace function public.submit_daily_puzzle(p_puzzle_date text)
returns integer
language plpgsql security definer set search_path = ''
as $$
declare
  v_date date;
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
  update public.daily_puzzle_attempts
  set completed_at = coalesce(completed_at, now()),
      completed_milliseconds = coalesce(
        completed_milliseconds,
        greatest(0, floor(extract(epoch from (now() - started_at)) * 1000)::integer)
      )
  where user_id = auth.uid() and puzzle_date = v_date
  returning completed_milliseconds into v_milliseconds;
  if v_milliseconds is null then
    raise exception 'Start the daily puzzle before submitting';
  end if;
  insert into public.daily_completions (user_id, puzzle_date)
  values (auth.uid(), v_date)
  on conflict do nothing;
  return v_milliseconds;
end;
$$;

create table if not exists public.recovery_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Bootstrap the current owner of @priscillaye. This UUID remains unchanged
-- when Apple is linked in place. The table, not the username, authorizes APIs.
insert into public.recovery_admins (user_id)
select id from public.profiles where username::text = 'priscillaye'
on conflict do nothing;

alter table public.recovery_admins enable row level security;
revoke all on table public.recovery_admins from anon, authenticated;

create table if not exists public.account_recovery_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  claimed_username text not null,
  note text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'completed')),
  old_user_id uuid references public.profiles(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  constraint recovery_username_format check (claimed_username ~ '^[a-z0-9_]{3,20}$')
);

create unique index if not exists one_open_recovery_per_requester
  on public.account_recovery_requests(requester_id)
  where status in ('pending', 'approved');

create unique index if not exists one_approved_recovery_per_old_account
  on public.account_recovery_requests(old_user_id)
  where status = 'approved';

alter table public.account_recovery_requests enable row level security;

drop policy if exists "Users can read their recovery requests" on public.account_recovery_requests;
create policy "Users can read their recovery requests"
  on public.account_recovery_requests for select to authenticated
  using (requester_id = auth.uid());

create or replace function public.is_recovery_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.recovery_admins a where a.user_id = auth.uid()
  );
$$;

create or replace function public.create_recovery_request(
  p_username text,
  p_note text default null
)
returns public.account_recovery_requests
language plpgsql security definer set search_path = ''
as $$
declare
  v_username text := lower(trim(p_username));
  v_request public.account_recovery_requests;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not exists (
    select 1 from auth.identities i
    where i.user_id = auth.uid() and i.provider = 'apple'
  ) then
    raise exception 'Sign in with Apple is required';
  end if;
  if v_username !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'Invalid username';
  end if;
  if v_username = 'priscillaye' then
    raise exception 'This account requires direct administrative support';
  end if;
  if not exists (select 1 from public.profiles p where p.username::text = v_username) then
    raise exception 'No account with that username was found';
  end if;
  insert into public.account_recovery_requests (requester_id, claimed_username, note)
  values (auth.uid(), v_username, nullif(left(trim(p_note), 1000), ''))
  returning * into v_request;
  return v_request;
end;
$$;

create or replace function public.list_my_recovery_requests()
returns setof public.account_recovery_requests
language sql stable security definer set search_path = ''
as $$
  select r.* from public.account_recovery_requests r
  where r.requester_id = auth.uid()
  order by r.created_at desc;
$$;

create or replace function public.admin_list_recovery_requests()
returns table (
  id uuid,
  requester_id uuid,
  claimed_username text,
  current_username text,
  note text,
  status text,
  old_user_id uuid,
  old_is_apple_backed boolean,
  old_friend_count bigint,
  old_completion_count bigint,
  created_at timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_recovery_admin() then raise exception 'Not authorized'; end if;
  return query
  select r.id, r.requester_id, r.claimed_username,
         current_profile.username::text, r.note, r.status, r.old_user_id,
         exists (
           select 1 from auth.identities i
           where i.user_id = old_profile.id and i.provider = 'apple'
         ),
         (select count(*) from public.friend_connections c
          where old_profile.id in (c.sender_id, c.receiver_id)),
         (select count(*) from public.daily_completions d
          where d.user_id = old_profile.id),
         r.created_at
  from public.account_recovery_requests r
  left join public.profiles current_profile on current_profile.id = r.requester_id
  left join public.profiles old_profile on old_profile.username::text = r.claimed_username
  order by case r.status when 'pending' then 0 when 'approved' then 1 else 2 end,
           r.created_at;
end;
$$;

create or replace function public.review_recovery_request(
  p_request_id uuid,
  p_approve boolean
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_old_user_id uuid;
begin
  if not public.is_recovery_admin() then raise exception 'Not authorized'; end if;
  select p.id into v_old_user_id
  from public.account_recovery_requests r
  join public.profiles p on p.username::text = r.claimed_username
  where r.id = p_request_id and r.status = 'pending'
  for update of r;
  if v_old_user_id is null then raise exception 'Recoverable account not found'; end if;
  if p_approve and exists (
    select 1 from auth.identities i
    where i.user_id = v_old_user_id and i.provider = 'apple'
  ) then
    raise exception 'This account is already protected by Sign in with Apple';
  end if;
  update public.account_recovery_requests
  set status = case when p_approve then 'approved' else 'rejected' end,
      old_user_id = case when p_approve then v_old_user_id else null end,
      reviewed_by = auth.uid(), reviewed_at = now()
  where id = p_request_id;
end;
$$;

create or replace function public.complete_recovery_request(p_request_id uuid)
returns public.profiles
language plpgsql security definer set search_path = ''
as $$
declare
  v_request public.account_recovery_requests;
  v_old public.profiles;
  v_destination public.profiles;
  v_connection public.friend_connections;
  v_existing_connection_id uuid;
  v_existing_connection_status text;
  v_new_sender_id uuid;
  v_new_receiver_id uuid;
  v_result public.profiles;
begin
  select * into v_request from public.account_recovery_requests
  where id = p_request_id and requester_id = auth.uid() and status = 'approved'
  for update;
  if v_request.id is null then raise exception 'Approved recovery request not found'; end if;
  if not exists (
    select 1 from auth.identities i
    where i.user_id = auth.uid() and i.provider = 'apple'
  ) then
    raise exception 'Sign in with Apple is required';
  end if;
  if v_request.old_user_id = auth.uid() then
    update public.account_recovery_requests set status = 'completed', completed_at = now()
    where id = v_request.id;
    select * into v_result from public.profiles where id = auth.uid();
    return v_result;
  end if;
  select * into v_old from public.profiles where id = v_request.old_user_id for update;
  select * into v_destination from public.profiles where id = auth.uid() for update;
  if v_old.id is null or v_destination.id is null then raise exception 'Account not found'; end if;
  if v_old.username::text is distinct from v_request.claimed_username then
    raise exception 'The claimed account changed after approval';
  end if;
  if exists (
    select 1 from auth.identities i
    where i.user_id = v_old.id and i.provider = 'apple'
  ) then
    raise exception 'This account is now protected by Sign in with Apple';
  end if;

  -- Release both names before assigning the recovered username.
  update public.profiles set username = null where id in (v_old.id, v_destination.id);
  update public.profiles
  set username = v_old.username,
      university_school_key = v_old.university_school_key,
      updated_at = now()
  where id = v_destination.id;

  for v_connection in
    select * from public.friend_connections
    where v_old.id in (sender_id, receiver_id)
  loop
    v_new_sender_id := case when v_connection.sender_id = v_old.id
                            then v_destination.id else v_connection.sender_id end;
    v_new_receiver_id := case when v_connection.receiver_id = v_old.id
                              then v_destination.id else v_connection.receiver_id end;
    if v_new_sender_id <> v_new_receiver_id then
      v_existing_connection_id := null;
      v_existing_connection_status := null;
      select c.id, c.status
      into v_existing_connection_id, v_existing_connection_status
      from public.friend_connections c
      where v_destination.id in (c.sender_id, c.receiver_id)
        and (case when c.sender_id = v_destination.id
                  then c.receiver_id else c.sender_id end) =
            (case when v_new_sender_id = v_destination.id
                  then v_new_receiver_id else v_new_sender_id end)
      limit 1
      for update;

      if v_existing_connection_id is null then
      insert into public.friend_connections (
        id, sender_id, receiver_id, status, created_at, responded_at
      ) values (
        gen_random_uuid(), v_new_sender_id, v_new_receiver_id,
        v_connection.status, v_connection.created_at, v_connection.responded_at
      );
      elsif v_existing_connection_status <> 'accepted'
            and v_connection.status in ('accepted', 'pending') then
        update public.friend_connections
        set sender_id = v_new_sender_id,
            receiver_id = v_new_receiver_id,
            status = v_connection.status,
            created_at = least(created_at, v_connection.created_at),
            responded_at = v_connection.responded_at
        where id = v_existing_connection_id;
      end if;
    end if;
  end loop;
  delete from public.friend_connections where v_old.id in (sender_id, receiver_id);

  insert into public.daily_completions (user_id, puzzle_date, completed_at)
  select v_destination.id, puzzle_date, completed_at
  from public.daily_completions where user_id = v_old.id
  on conflict do nothing;

  delete from public.daily_solve_notifications
  where solver_id = v_old.id or recipient_id = v_old.id;
  insert into public.daily_puzzle_attempts (
    user_id, puzzle_date, numbers, started_at, completed_at, completed_milliseconds
  )
  select v_destination.id, puzzle_date, numbers, started_at, completed_at, completed_milliseconds
  from public.daily_puzzle_attempts where user_id = v_old.id
  on conflict do nothing;

  update public.device_tokens set user_id = v_destination.id where user_id = v_old.id;
  update public.rooms set host_user_id = v_destination.id where host_user_id = v_old.id;
  delete from public.profiles where id = v_old.id;
  delete from auth.users where id = v_old.id;

  update public.account_recovery_requests
  set status = 'completed', completed_at = now()
  where id = v_request.id;
  select * into v_result from public.profiles where id = v_destination.id;
  return v_result;
end;
$$;

revoke all on function public.list_daily_completion_dates() from public;
revoke all on function public.merge_daily_completion_dates(text[]) from public;
revoke all on function public.is_recovery_admin() from public;
revoke all on function public.create_recovery_request(text, text) from public;
revoke all on function public.list_my_recovery_requests() from public;
revoke all on function public.admin_list_recovery_requests() from public;
revoke all on function public.review_recovery_request(uuid, boolean) from public;
revoke all on function public.complete_recovery_request(uuid) from public;

grant execute on function public.list_daily_completion_dates() to authenticated;
grant execute on function public.merge_daily_completion_dates(text[]) to authenticated;
grant execute on function public.is_recovery_admin() to authenticated;
grant execute on function public.create_recovery_request(text, text) to authenticated;
grant execute on function public.list_my_recovery_requests() to authenticated;
grant execute on function public.admin_list_recovery_requests() to authenticated;
grant execute on function public.review_recovery_request(uuid, boolean) to authenticated;
grant execute on function public.complete_recovery_request(uuid) to authenticated;
