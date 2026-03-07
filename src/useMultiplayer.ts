import { useState, useRef, useCallback } from 'react'
import {
  supabase,
  createRoom, joinRoom, fetchPlayers,
  leaveRoom as svcLeaveRoom,
  startRound, submitSolution as svcSubmitSolution,
  pingPlayer, setTotalRounds, completeGame, resetRoom,
} from './supabase'
import type { RoomRow, PlayerRow, SubmissionRow } from './supabase'
import { Fraction, findAllSolutions } from './game'

// MARK: - Types

export type LobbyState =
  | { kind: 'nameEntry' }
  | { kind: 'loading' }
  | { kind: 'waitingRoom' }
  | { kind: 'playing' }
  | { kind: 'roundOver'; winnerName: string; didWin: boolean }
  | { kind: 'dissolved'; reason: string }
  | { kind: 'gameOver' }

export interface MpState {
  lobbyState: LobbyState
  displayName: string
  joinCode: string
  errorMessage: string | null
  players: PlayerRow[]
  currentRoom: RoomRow | null
  myPlayerId: string | null
  isHost: boolean
  gameNumbers: number[] | null
  totalRounds: number
}

// MARK: - Helpers

function generateSolvablePuzzle(): number[] {
  let nums: number[]
  do {
    nums = Array.from({ length: 4 }, () => Math.floor(Math.random() * 13) + 1)
  } while (findAllSolutions(nums.map(n => new Fraction(n))).length === 0)
  return nums
}

// MARK: - Hook

export function useMultiplayer() {
  const [state, setState] = useState<MpState>({
    lobbyState: { kind: 'nameEntry' },
    displayName: '',
    joinCode: '',
    errorMessage: null,
    players: [],
    currentRoom: null,
    myPlayerId: null,
    isHost: false,
    gameNumbers: null,
    totalRounds: 5,
  })

  // Always-current ref so realtime callbacks don't close over stale state
  const stateRef = useRef(state)
  stateRef.current = state

  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null)
  const heartbeatRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const merge = useCallback((partial: Partial<MpState>) => {
    setState(s => ({ ...s, ...partial }))
  }, [])

  const stopSubscriptions = useCallback(() => {
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current)
      channelRef.current = null
    }
    if (heartbeatRef.current) {
      clearInterval(heartbeatRef.current)
      heartbeatRef.current = null
    }
  }, [])

  const resetToNameEntry = useCallback(() => {
    stopSubscriptions()
    setState(s => ({
      ...s,
      lobbyState: { kind: 'nameEntry' },
      errorMessage: null,
      players: [],
      currentRoom: null,
      myPlayerId: null,
      isHost: false,
      gameNumbers: null,
    }))
  }, [stopSubscriptions])

  const beginSubscriptions = useCallback((roomId: string) => {
    const channel = supabase
      .channel(`room-${roomId}`)
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'rooms', filter: `id=eq.${roomId}` },
        (payload) => {
          const room = payload.new as RoomRow
          setState(s => ({
            ...s,
            currentRoom: room,
            // Non-host learns totalRounds from DB; host already set it locally
            totalRounds: s.isHost ? s.totalRounds : (room.total_rounds ?? s.totalRounds),
          }))
          if (room.status === 'playing' && room.numbers?.length === 4) {
            setState(s => ({ ...s, gameNumbers: room.numbers, lobbyState: { kind: 'playing' } }))
          } else if (room.status === 'finished') {
            // keep channel alive so we can receive a play-again reset
            if (room.round >= room.total_rounds) {
              setState(s => ({ ...s, lobbyState: { kind: 'gameOver' } }))
            } else {
              setState(s => ({ ...s, lobbyState: { kind: 'dissolved', reason: 'The host ended the game.' } }))
            }
          } else if (room.status === 'waiting') {
            setState(s => ({ ...s, lobbyState: { kind: 'waitingRoom' }, totalRounds: 5, gameNumbers: null }))
          }
        },
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'players', filter: `room_id=eq.${roomId}` },
        async () => {
          try {
            const players = await fetchPlayers(roomId)
            setState(s => ({ ...s, players }))
          } catch { /* ignore */ }
        },
      )
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'submissions', filter: `room_id=eq.${roomId}` },
        (payload) => {
          const submission = payload.new as SubmissionRow
          const s = stateRef.current
          if (!s.currentRoom || submission.round !== s.currentRoom.round) return

          const winner = s.players.find(p => p.id === submission.player_id)
          const winnerName = winner?.display_name ?? 'Someone'
          const didWin = submission.player_id === s.myPlayerId

          setState(prev => ({
            ...prev,
            lobbyState: { kind: 'roundOver', winnerName, didWin },
            players: prev.players.map(p =>
              p.id === submission.player_id ? { ...p, score: p.score + 1 } : p
            ),
          }))

          // Host schedules the next round or ends the game
          const submittedRound = submission.round       // from the event payload, always correct
          const totalRounds = s.totalRounds             // from MpState, never overwritten by DB events
          if (stateRef.current.isHost) {
            setTimeout(async () => {
              const cur = stateRef.current
              if (!cur.currentRoom || !cur.myPlayerId) return
              try {
                if (submittedRound >= totalRounds) {
                  await completeGame(cur.currentRoom.id)
                } else {
                  await startRound(cur.currentRoom.id, cur.myPlayerId, generateSolvablePuzzle())
                }
              } catch { /* ignore */ }
            }, 2800)
          }
        },
      )
      .subscribe()

    channelRef.current = channel
  }, [stopSubscriptions])

  const startHeartbeat = useCallback((playerId: string) => {
    if (heartbeatRef.current) clearInterval(heartbeatRef.current)
    heartbeatRef.current = setInterval(() => { pingPlayer(playerId) }, 15000)
  }, [])

  // MARK: - Actions

  const doCreateRoom = useCallback(async () => {
    const name = stateRef.current.displayName.trim()
    if (!name) { merge({ errorMessage: 'Enter a display name first.' }); return }
    merge({ lobbyState: { kind: 'loading' }, errorMessage: null })
    try {
      const { room, player } = await createRoom(name)
      merge({ myPlayerId: player.id, isHost: true, currentRoom: room, players: [player], lobbyState: { kind: 'waitingRoom' } })
      beginSubscriptions(room.id)
      startHeartbeat(player.id)
    } catch (e) {
      merge({ errorMessage: (e as Error).message, lobbyState: { kind: 'nameEntry' } })
    }
  }, [merge, beginSubscriptions, startHeartbeat])

  const doJoinRoom = useCallback(async () => {
    const name = stateRef.current.displayName.trim()
    const code = stateRef.current.joinCode.trim().toUpperCase()
    if (!name) { merge({ errorMessage: 'Enter a display name first.' }); return }
    if (code.length !== 6) { merge({ errorMessage: 'Enter a valid 6-character room code.' }); return }
    merge({ lobbyState: { kind: 'loading' }, errorMessage: null })
    try {
      const { room, player } = await joinRoom(code, name)
      const players = await fetchPlayers(room.id)
      merge({ myPlayerId: player.id, isHost: false, currentRoom: room, players, lobbyState: { kind: 'waitingRoom' } })
      beginSubscriptions(room.id)
      startHeartbeat(player.id)
    } catch (e) {
      merge({ errorMessage: (e as Error).message, lobbyState: { kind: 'nameEntry' } })
    }
  }, [merge, beginSubscriptions, startHeartbeat])

  const doStartGame = useCallback(async (totalRounds: number) => {
    const s = stateRef.current
    if (!s.isHost || !s.currentRoom || !s.myPlayerId || s.players.length < 2) return
    try {
      merge({ totalRounds })  // set authoritatively before any DB round-trips
      await startRound(s.currentRoom.id, s.myPlayerId, generateSolvablePuzzle())
      await setTotalRounds(s.currentRoom.id, totalRounds)  // after RPC, overwriting any default reset
    } catch (e) {
      merge({ errorMessage: (e as Error).message })
    }
  }, [merge])

  const doLeaveRoom = useCallback(async () => {
    const s = stateRef.current
    stopSubscriptions()
    if (s.myPlayerId && s.currentRoom) {
      try { await svcLeaveRoom(s.myPlayerId, s.currentRoom.id, s.isHost) } catch { /* ignore */ }
    }
    resetToNameEntry()
  }, [stopSubscriptions, resetToNameEntry])

  const doSubmitSolution = useCallback(async (solutionStr: string): Promise<boolean> => {
    const s = stateRef.current
    if (!s.currentRoom || !s.myPlayerId) return false
    try {
      return await svcSubmitSolution(s.currentRoom.id, s.myPlayerId, s.currentRoom.round, solutionStr)
    } catch (e) {
      merge({ errorMessage: (e as Error).message })
      return false
    }
  }, [merge])

  const doPlayAgain = useCallback(async () => {
    const s = stateRef.current
    if (!s.isHost || !s.currentRoom) return
    try {
      await resetRoom(s.currentRoom.id)
      merge({ lobbyState: { kind: 'waitingRoom' }, totalRounds: 5, gameNumbers: null })
    } catch (e) {
      merge({ errorMessage: (e as Error).message })
    }
  }, [merge])

  const dismissError = useCallback(() => {
    const kind = stateRef.current.lobbyState.kind
    if (kind === 'dissolved' || kind === 'gameOver') {
      resetToNameEntry()
    } else {
      merge({ errorMessage: null })
    }
  }, [merge, resetToNameEntry])

  return {
    state,
    setDisplayName: (v: string) => merge({ displayName: v }),
    setJoinCode: (v: string) => merge({ joinCode: v.slice(0, 6).toUpperCase() }),
    doCreateRoom,
    doJoinRoom,
    doStartGame,
    doLeaveRoom,
    doSubmitSolution,
    doPlayAgain,
    dismissError,
  }
}
