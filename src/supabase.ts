import { createClient } from '@supabase/supabase-js'

export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL as string,
  import.meta.env.VITE_SUPABASE_KEY as string,
)

// MARK: - Types

export interface RoomRow {
  id: string
  code: string
  host_id: string
  status: 'waiting' | 'playing' | 'finished'
  numbers: number[] | null
  round: number
}

export interface PlayerRow {
  id: string
  room_id: string
  display_name: string
  score: number
  is_host: boolean
}

export interface SubmissionRow {
  id: string
  room_id: string
  player_id: string
  round: number
  solution: string
}

// MARK: - Code generation

function generateCode(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  return Array.from({ length: 6 }, () => chars[Math.floor(Math.random() * chars.length)]).join('')
}

// MARK: - Service

export async function createRoom(displayName: string): Promise<{ room: RoomRow; player: PlayerRow }> {
  const playerId = crypto.randomUUID()

  let room: RoomRow | null = null
  for (let i = 0; i < 10; i++) {
    const { data, error } = await supabase
      .from('rooms')
      .insert({ code: generateCode(), host_id: playerId })
      .select()
      .single()
    if (!error && data) { room = data as RoomRow; break }
  }
  if (!room) throw new Error('Failed to create room. Please try again.')

  const { data: player, error: playerErr } = await supabase
    .from('players')
    .insert({ id: playerId, room_id: room.id, display_name: displayName, is_host: true })
    .select()
    .single()
  if (playerErr || !player) throw new Error(playerErr?.message ?? 'Failed to create player.')

  return { room, player: player as PlayerRow }
}

export async function joinRoom(code: string, displayName: string): Promise<{ room: RoomRow; player: PlayerRow }> {
  const { data: rooms, error } = await supabase
    .from('rooms')
    .select()
    .eq('code', code.toUpperCase())
    .eq('status', 'waiting')
    .limit(1)
  if (error) throw new Error(error.message)
  if (!rooms?.length) throw new Error('Room not found or already started.')

  const room = rooms[0] as RoomRow
  const playerId = crypto.randomUUID()

  const { data: player, error: playerErr } = await supabase
    .from('players')
    .insert({ id: playerId, room_id: room.id, display_name: displayName, is_host: false })
    .select()
    .single()
  if (playerErr || !player) throw new Error(playerErr?.message ?? 'Failed to join room.')

  return { room, player: player as PlayerRow }
}

export async function fetchPlayers(roomId: string): Promise<PlayerRow[]> {
  const { data, error } = await supabase
    .from('players')
    .select()
    .eq('room_id', roomId)
    .order('joined_at')
  if (error) throw new Error(error.message)
  return (data ?? []) as PlayerRow[]
}

export async function leaveRoom(playerId: string, roomId: string, isHost: boolean): Promise<void> {
  if (isHost) {
    await supabase.rpc('dissolve_room', { p_room_id: roomId, p_host_id: playerId })
  } else {
    await supabase.from('players').delete().eq('id', playerId)
  }
}

export async function startRound(roomId: string, hostPlayerId: string, numbers: number[]): Promise<void> {
  const { error } = await supabase.rpc('start_round', {
    p_room_id: roomId,
    p_host_player_id: hostPlayerId,
    p_numbers: numbers,
  })
  if (error) throw new Error(error.message)
}

export async function submitSolution(
  roomId: string,
  playerId: string,
  round: number,
  solution: string,
): Promise<boolean> {
  const { data, error } = await supabase.rpc('claim_round_win', {
    p_room_id: roomId,
    p_player_id: playerId,
    p_round: round,
    p_solution: solution,
  })
  if (error) throw new Error(error.message)
  return data as boolean
}

export async function pingPlayer(playerId: string): Promise<void> {
  await supabase
    .from('players')
    .update({ last_ping: new Date().toISOString() })
    .eq('id', playerId)
}
