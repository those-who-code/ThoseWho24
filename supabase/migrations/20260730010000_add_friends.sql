create extension if not exists citext with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username extensions.citext unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (
    username is null
    or username::text ~ '^[a-z0-9_]{3,20}$'
  )
);

create table if not exists public.friend_connections (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'rejected')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint different_users check (sender_id <> receiver_id)
);

create unique index if not exists friend_connections_unique_pair
  on public.friend_connections (
    least(sender_id, receiver_id),
    greatest(sender_id, receiver_id)
  );

create index if not exists friend_connections_sender_idx
  on public.friend_connections(sender_id, status);

create index if not exists friend_connections_receiver_idx
  on public.friend_connections(receiver_id, status);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null default 'ios' check (platform = 'ios'),
  environment text not null default 'development'
    check (environment in ('development', 'production')),
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_idx
  on public.device_tokens(user_id);

alter table public.profiles enable row level security;
alter table public.friend_connections enable row level security;
alter table public.device_tokens enable row level security;

drop policy if exists "Profiles are readable by signed-in users" on public.profiles;
create policy "Profiles are readable by signed-in users"
  on public.profiles for select
  to authenticated
  using (username is not null or id = auth.uid());

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "Participants can read connections" on public.friend_connections;
create policy "Participants can read connections"
  on public.friend_connections for select
  to authenticated
  using (auth.uid() in (sender_id, receiver_id));

drop policy if exists "Users can register their devices" on public.device_tokens;
create policy "Users can register their devices"
  on public.device_tokens for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update their devices" on public.device_tokens;
create policy "Users can update their devices"
  on public.device_tokens for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users can remove their devices" on public.device_tokens;
create policy "Users can remove their devices"
  on public.device_tokens for delete
  to authenticated
  using (user_id = auth.uid());

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into public.profiles (id)
select id from auth.users
on conflict (id) do nothing;

create or replace function public.set_username(p_username text)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_username text := lower(trim(p_username));
  v_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if v_username !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'Username must be 3–20 characters using letters, numbers, or underscores';
  end if;

  update public.profiles
    set username = v_username, updated_at = now()
    where id = auth.uid()
    returning * into v_profile;

  return v_profile;
exception
  when unique_violation then
    raise exception 'That username is already taken';
end;
$$;

create or replace function public.search_profiles(p_query text)
returns table (
  user_id uuid,
  username text,
  mutual_friend_count bigint,
  relationship_state text
)
language sql
stable
security definer
set search_path = ''
as $$
  with my_friends as (
    select case
      when c.sender_id = auth.uid() then c.receiver_id
      else c.sender_id
    end as friend_id
    from public.friend_connections c
    where c.status = 'accepted'
      and auth.uid() in (c.sender_id, c.receiver_id)
  ),
  candidates as (
    select p.id, p.username
    from public.profiles p
    where p.id <> auth.uid()
      and p.username is not null
      and p.username::text like lower(trim(p_query)) || '%'
    order by p.username
    limit 30
  )
  select
    p.id,
    p.username::text,
    (
      select count(*)
      from public.friend_connections theirs
      join my_friends mine
        on mine.friend_id = case
          when theirs.sender_id = p.id then theirs.receiver_id
          else theirs.sender_id
        end
      where theirs.status = 'accepted'
        and p.id in (theirs.sender_id, theirs.receiver_id)
    ),
    coalesce((
      select case
        when c.status = 'accepted' then 'friends'
        when c.status = 'pending' and c.sender_id = auth.uid() then 'outgoing'
        when c.status = 'pending' then 'incoming'
        else 'none'
      end
      from public.friend_connections c
      where auth.uid() in (c.sender_id, c.receiver_id)
        and p.id in (c.sender_id, c.receiver_id)
      limit 1
    ), 'none')
  from candidates p;
$$;

create or replace function public.list_friend_connections()
returns table (
  request_id uuid,
  user_id uuid,
  username text,
  status text,
  direction text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    c.id,
    other.id,
    other.username::text,
    c.status,
    case when c.sender_id = auth.uid() then 'outgoing' else 'incoming' end,
    c.created_at
  from public.friend_connections c
  join public.profiles other
    on other.id = case
      when c.sender_id = auth.uid() then c.receiver_id
      else c.sender_id
    end
  where auth.uid() in (c.sender_id, c.receiver_id)
    and c.status in ('pending', 'accepted')
  order by
    case when c.status = 'pending' and c.receiver_id = auth.uid() then 0
         when c.status = 'pending' then 1 else 2 end,
    c.created_at desc;
$$;

create or replace function public.send_friend_request(p_receiver_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_existing public.friend_connections;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_receiver_id = auth.uid() then
    raise exception 'You cannot add yourself';
  end if;
  if not exists (
    select 1 from public.profiles
    where id = p_receiver_id and username is not null
  ) then
    raise exception 'User not found';
  end if;

  select * into v_existing
  from public.friend_connections
  where least(sender_id, receiver_id) = least(auth.uid(), p_receiver_id)
    and greatest(sender_id, receiver_id) = greatest(auth.uid(), p_receiver_id);

  if v_existing.status in ('pending', 'accepted') then
    raise exception 'A friendship or request already exists';
  elsif v_existing.id is not null then
    update public.friend_connections
      set sender_id = auth.uid(), receiver_id = p_receiver_id,
          status = 'pending', created_at = now(), responded_at = null
      where id = v_existing.id
      returning id into v_id;
  else
    insert into public.friend_connections (sender_id, receiver_id)
      values (auth.uid(), p_receiver_id)
      returning id into v_id;
  end if;

  return v_id;
end;
$$;

create or replace function public.respond_to_friend_request(
  p_request_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.friend_connections
    set status = case when p_accept then 'accepted' else 'rejected' end,
        responded_at = now()
    where id = p_request_id
      and receiver_id = auth.uid()
      and status = 'pending';

  if not found then
    raise exception 'Pending request not found';
  end if;
end;
$$;

create or replace function public.remove_friend_connection(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.friend_connections
  where auth.uid() in (sender_id, receiver_id)
    and p_user_id in (sender_id, receiver_id);

  if not found then
    raise exception 'Connection not found';
  end if;
end;
$$;

create or replace function public.register_device_token(
  p_token text,
  p_environment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_environment not in ('development', 'production') then
    raise exception 'Invalid APNs environment';
  end if;

  insert into public.device_tokens (user_id, token, environment, updated_at)
    values (auth.uid(), p_token, p_environment, now())
  on conflict (token) do update
    set user_id = auth.uid(),
        environment = excluded.environment,
        updated_at = now();
end;
$$;

revoke all on function public.set_username(text) from public;
revoke all on function public.search_profiles(text) from public;
revoke all on function public.list_friend_connections() from public;
revoke all on function public.send_friend_request(uuid) from public;
revoke all on function public.respond_to_friend_request(uuid, boolean) from public;
revoke all on function public.remove_friend_connection(uuid) from public;
revoke all on function public.register_device_token(text, text) from public;

grant execute on function public.set_username(text) to authenticated;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.list_friend_connections() to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.respond_to_friend_request(uuid, boolean) to authenticated;
grant execute on function public.remove_friend_connection(uuid) to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.friend_connections;
exception
  when duplicate_object then null;
end $$;
