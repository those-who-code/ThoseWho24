-- In-app account deletion and multiplayer ownership hardening.

alter table public.players
  add column if not exists user_id uuid
  default auth.uid() references auth.users(id) on delete cascade;

create index if not exists players_user_idx on public.players(user_id);

drop policy if exists "Signed-in users can create rooms" on public.rooms;
create policy "Signed-in users can create rooms"
  on public.rooms for insert to authenticated
  with check (host_user_id = auth.uid());

drop policy if exists "Users can create their own player" on public.players;
create policy "Users can create their own player"
  on public.players for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists "Users can update their own player" on public.players;
create policy "Users can update their own player"
  on public.players for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "Users can delete their own player" on public.players;
create policy "Users can delete their own player"
  on public.players for delete to authenticated
  using (user_id = auth.uid());

-- Recreate the multiplayer mutations after host_user_id is available. New
-- rooms and player records are bound to the authenticated account.
create or replace function public.start_round(
  p_room_id uuid,
  p_host_player_id uuid,
  p_numbers integer[]
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_room public.rooms;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if cardinality(p_numbers) <> 4
     or not (p_numbers <@ array[1,2,3,4,5,6,7,8,9,10,11,12,13]) then
    raise exception 'Invalid puzzle numbers';
  end if;
  select * into v_room from public.rooms
  where id = p_room_id for update;
  if v_room.id is null or v_room.host_id <> p_host_player_id
     or v_room.host_user_id <> auth.uid() then
    raise exception 'Only the host can start a round';
  end if;
  if v_room.status = 'finished' then raise exception 'Room has ended'; end if;
  if not exists (
    select 1 from public.players p
    where p.id = p_host_player_id and p.room_id = p_room_id
      and p.is_host and p.user_id = auth.uid()
  ) then
    raise exception 'Only the host can start a round';
  end if;
  if v_room.round > 0 and exists (
    select 1 from public.players p
    where p.room_id = p_room_id and p.ready_round < v_room.round
  ) then
    raise exception 'Players are not ready';
  end if;
  update public.rooms
  set status = 'playing', numbers = p_numbers, round = round + 1
  where id = p_room_id;
end;
$$;

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
  if nullif(trim(p_solution), '') is null or char_length(p_solution) > 4000 then
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

create or replace function public.dissolve_room(
  p_room_id uuid,
  p_host_id uuid
)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.rooms
  set status = 'finished'
  where id = p_room_id and host_id = p_host_id
    and host_user_id = auth.uid();
  if not found then raise exception 'Only the host can end this room'; end if;
end;
$$;

create or replace function public.delete_my_account()
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_user_id uuid := auth.uid();
begin
  if v_user_id is null then raise exception 'Authentication required'; end if;
  if exists (
    select 1 from public.recovery_admins where user_id = v_user_id
  ) then
    raise exception 'The recovery administrator account cannot be deleted while recovery is enabled';
  end if;

  -- Hosted rooms and their player/submission rows are ephemeral and should not
  -- survive their owner's account. Guest player rows are removed separately.
  delete from public.rooms where host_user_id = v_user_id;
  delete from public.players where user_id = v_user_id;
  delete from auth.users where id = v_user_id;
  if not found then raise exception 'Account not found'; end if;
end;
$$;

revoke all on function public.start_round(uuid, uuid, integer[]) from public;
revoke all on function public.claim_round_win(uuid, uuid, integer, text) from public;
revoke all on function public.dissolve_room(uuid, uuid) from public;
revoke all on function public.delete_my_account() from public;
grant execute on function public.start_round(uuid, uuid, integer[]) to authenticated;
grant execute on function public.claim_round_win(uuid, uuid, integer, text) to authenticated;
grant execute on function public.dissolve_room(uuid, uuid) to authenticated;
grant execute on function public.delete_my_account() to authenticated;
