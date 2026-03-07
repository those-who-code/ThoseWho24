import { useState, useEffect, useRef } from 'react'
import { useMultiplayer } from './useMultiplayer'
import { useGameWithNumbers } from './useGame'
import { OPERATORS } from './game'
import type { MathOperator } from './game'
import type { PlayerRow } from './supabase'
import { recordSolve, problemKeyFromNumbers } from './stats'

// MARK: - Scoreboard

function Scoreboard({ players, myPlayerId }: { players: PlayerRow[]; myPlayerId: string | null }) {
  return (
    <div className="scoreboard">
      {players.map(p => {
        const isMe = p.id === myPlayerId
        return (
          <div key={p.id} className={`score-cell ${isMe ? 'score-cell--me' : ''}`}>
            <span className="score-value">{p.score}</span>
            <span className="score-name">{p.display_name}</span>
          </div>
        )
      })}
    </div>
  )
}

// MARK: - Multiplayer Game

function MultiplayerGame({
  numbers,
  players,
  myPlayerId,
  round,
  totalRounds,
  onSubmit,
  onLeave,
}: {
  numbers: number[]
  players: PlayerRow[]
  myPlayerId: string | null
  round: number
  totalRounds: number
  onSubmit: (solutionStr: string, elapsedSeconds: number) => void
  onLeave: () => void
}) {
  const game = useGameWithNumbers(numbers)

  const onSubmitRef = useRef(onSubmit)
  onSubmitRef.current = onSubmit

  useEffect(() => {
    if (!game.didWin) return
    const solutionStr =
      game.allSolutions[0]?.map(s => `${s.a} ${s.op} ${s.b} = ${s.result}`).join(', ') ?? 'solved'
    onSubmitRef.current(solutionStr, game.elapsedSeconds)
  }, [game.didWin])

  const handleCardTap = (i: number) => game.dispatch({ type: 'CARD_TAP', index: i })
  const handleSelectOp = (op: MathOperator) => game.dispatch({ type: 'SELECT_OPERATOR', op })
  const handleUndo = () => game.dispatch({ type: 'UNDO' })

  return (
    <div className="game-view">
      {/* Top bar */}
      <div className="top-bar">
        <button className="mp-back-btn" onClick={onLeave}>← Leave</button>
        <span className="mp-round-label">Round {round} / {totalRounds}</span>
        <span style={{ width: 64 }} />
      </div>

      {/* Scoreboard */}
      <div style={{ padding: '12px 24px 0' }}>
        <Scoreboard players={players} myPlayerId={myPlayerId} />
      </div>

      {/* Message */}
      <p className="game-message">{game.message}</p>

      {/* Cards */}
      <div className="card-grid">
        {game.cards.map((card, i) => (
          <button
            key={card.id}
            className={`card ${game.selectedCardIndex === i ? 'card--selected' : ''} ${!card.isVisible ? 'card--hidden' : ''}`}
            onClick={() => handleCardTap(i)}
            tabIndex={card.isVisible ? 0 : -1}
          >
            {card.value.isWhole
              ? <span className="card-number">{card.value.num}</span>
              : <span className={`card-fraction ${game.selectedCardIndex === i ? 'card-fraction--selected' : ''}`}>
                  <span>{card.value.num}</span>
                  <span className="fraction-divider" />
                  <span>{card.value.den}</span>
                </span>
            }
          </button>
        ))}
      </div>

      {/* Operators */}
      <div className="operator-bar">
        {OPERATORS.map(op => (
          <button
            key={op}
            className={`operator-btn ${game.selectedOperator === op ? 'operator-btn--selected' : ''}`}
            onClick={() => handleSelectOp(op)}
          >
            {op}
          </button>
        ))}
      </div>

      {/* Bottom buttons */}
      <div className="bottom-buttons">
        <button
          className={`bottom-btn ${!game.canUndo ? 'bottom-btn--disabled' : ''}`}
          onClick={handleUndo}
          disabled={!game.canUndo}
        >
          <span className="bottom-btn-icon">↩</span> Undo
        </button>
      </div>
    </div>
  )
}

// MARK: - Round Result Overlay

function RoundResultOverlay({ winnerName, didWin }: { winnerName: string; didWin: boolean }) {
  return (
    <div className="round-overlay">
      <div className="round-overlay-content">
        <p className="round-overlay-title">
          {didWin ? 'You solved it!' : `${winnerName} was faster`}
        </p>
        {!didWin && (
          <p className="round-overlay-sub">Next round coming up...</p>
        )}
      </div>
    </div>
  )
}

// MARK: - Waiting Room

const ROUND_OPTIONS = [5, 10, 20] as const

function WaitingRoomView({
  players,
  currentRoom,
  isHost,
  onStartGame,
  onLeave,
}: {
  players: PlayerRow[]
  currentRoom: { code: string } | null
  isHost: boolean
  onStartGame: (totalRounds: number) => void
  onLeave: () => void
}) {
  const [copied, setCopied] = useState(false)
  const [roundCount, setRoundCount] = useState<number>(5)
  const [isCustom, setIsCustom] = useState(false)
  const [customValue, setCustomValue] = useState('')

  const copyCode = () => {
    if (!currentRoom) return
    navigator.clipboard.writeText(currentRoom.code)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <div className="lobby-view">
      <div className="top-bar">
        <button className="mp-back-btn" onClick={onLeave}>← Leave</button>
      </div>

      <div className="lobby-body">
        {/* Room code */}
        <div className="room-code-section">
          <p className="room-code-label">Room Code</p>
          <button className="room-code-btn" onClick={copyCode}>
            <span className="room-code-value">{currentRoom?.code ?? '------'}</span>
            <span className="room-code-copy">{copied ? '✓' : '⎘'}</span>
          </button>
          {copied && <p className="room-code-copied">Copied!</p>}
        </div>

        {/* Players */}
        <div className="waiting-players">
          <p className="waiting-players-count">
            {players.length} player{players.length === 1 ? '' : 's'}
          </p>
          <div className="waiting-players-list">
            {players.map((p, i) => (
              <div key={p.id}>
                <div className="waiting-player-row">
                  <span className="waiting-player-name">{p.display_name}</span>
                  {p.is_host && <span className="waiting-player-host">Host</span>}
                </div>
                {i < players.length - 1 && <div className="waiting-divider" />}
              </div>
            ))}
          </div>
        </div>

        {players.length < 2 && (
          <p className="waiting-status">Waiting for more players...</p>
        )}
      </div>

      <div style={{ padding: '0 32px 40px', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {isHost && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <p className="waiting-players-count">Rounds</p>
            <div className="mp-mode-picker">
              {ROUND_OPTIONS.map(n => (
                <button
                  key={n}
                  className={`mp-mode-btn ${!isCustom && roundCount === n ? 'mp-mode-btn--active' : ''}`}
                  onClick={() => { setRoundCount(n); setIsCustom(false) }}
                >
                  {n}
                </button>
              ))}
              <button
                className={`mp-mode-btn ${isCustom ? 'mp-mode-btn--active' : ''}`}
                onClick={() => setIsCustom(true)}
              >
                Custom
              </button>
            </div>
            {isCustom && (
              <input
                className="mp-input mp-input--mono"
                type="number"
                min={1}
                placeholder="Enter rounds"
                value={customValue}
                onChange={e => {
                  setCustomValue(e.target.value)
                  const n = parseInt(e.target.value, 10)
                  if (!isNaN(n) && n > 0) setRoundCount(n)
                }}
                autoFocus
              />
            )}
          </div>
        )}
        {isHost ? (
          <button
            className={`mp-action-btn ${players.length < 2 || (isCustom && !(parseInt(customValue, 10) > 0)) ? 'mp-action-btn--disabled' : ''}`}
            onClick={() => onStartGame(roundCount)}
            disabled={players.length < 2 || (isCustom && !(parseInt(customValue, 10) > 0))}
          >
            Start Game
          </button>
        ) : (
          <p className="waiting-status" style={{ paddingBottom: 8 }}>
            Waiting for host to start...
          </p>
        )}
      </div>
    </div>
  )
}

// MARK: - Game Over

function GameOverView({ players, myPlayerId, isHost, onPlayAgain, onBack }: {
  players: PlayerRow[]
  myPlayerId: string | null
  isHost: boolean
  onPlayAgain: () => void
  onBack: () => void
}) {
  const sorted = [...players].sort((a, b) => b.score - a.score)
  const winner = sorted[0]
  return (
    <div className="gameover-view">
      <h1 className="gameover-title">Game Over</h1>
      {winner && (
        <div style={{ textAlign: 'center' }}>
          <p className="gameover-winner">{winner.display_name}</p>
          <p className="gameover-winner-sub">wins!</p>
        </div>
      )}
      <div className="gameover-scores">
        {sorted.map((p, i) => (
          <div key={p.id} className={`gameover-row ${p.id === myPlayerId ? 'gameover-row--me' : ''}`}>
            <span className="gameover-rank">#{i + 1}</span>
            <span className="gameover-name">{p.display_name}</span>
            <span className="gameover-score">{p.score}</span>
          </div>
        ))}
      </div>
      <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 12 }}>
        {isHost && (
          <button className="mp-action-btn" onClick={onPlayAgain}>Play Again</button>
        )}
        <button className="mp-action-btn" style={{ background: 'rgba(0,0,0,0.07)', color: '#000' }} onClick={onBack}>
          Back to Menu
        </button>
      </div>
    </div>
  )
}

// MARK: - Lobby (Create / Join)

function LobbyView({
  displayName,
  joinCode,
  isLoading,
  onDisplayNameChange,
  onJoinCodeChange,
  onCreateRoom,
  onJoinRoom,
  onExit,
}: {
  displayName: string
  joinCode: string
  isLoading: boolean
  onDisplayNameChange: (v: string) => void
  onJoinCodeChange: (v: string) => void
  onCreateRoom: () => void
  onJoinRoom: () => void
  onExit: () => void
}) {
  const [mode, setMode] = useState<'create' | 'join'>('create')

  const handleAction = () => {
    if (mode === 'create') onCreateRoom()
    else onJoinRoom()
  }

  return (
    <div className="lobby-view">
      <div className="top-bar">
        <button className="mp-close-btn" onClick={onExit}>✕</button>
      </div>

      <div className="lobby-body">
        <div className="lobby-title-section">
          <h1 className="lobby-title">Multiplayer</h1>
          <p className="lobby-subtitle">Race to make 24</p>
        </div>

        {/* Mode picker */}
        <div className="mp-mode-picker">
          {(['create', 'join'] as const).map(m => (
            <button
              key={m}
              className={`mp-mode-btn ${mode === m ? 'mp-mode-btn--active' : ''}`}
              onClick={() => setMode(m)}
            >
              {m === 'create' ? 'Create' : 'Join'}
            </button>
          ))}
        </div>

        {/* Inputs */}
        <div className="lobby-inputs">
          <input
            className="mp-input"
            type="text"
            placeholder="Display name"
            value={displayName}
            onChange={e => onDisplayNameChange(e.target.value)}
            autoCapitalize="words"
            autoComplete="off"
          />
          {mode === 'join' && (
            <input
              className="mp-input mp-input--mono"
              type="text"
              placeholder="Room code (e.g. ABC123)"
              value={joinCode}
              onChange={e => onJoinCodeChange(e.target.value)}
              autoCapitalize="characters"
              autoComplete="off"
              onKeyDown={e => e.key === 'Enter' && handleAction()}
            />
          )}
        </div>

        <button
          className={`mp-action-btn ${isLoading ? 'mp-action-btn--loading' : ''}`}
          onClick={handleAction}
          disabled={isLoading}
        >
          {isLoading
            ? <span className="mp-spinner" />
            : mode === 'create' ? 'Create Room' : 'Join Room'
          }
        </button>
      </div>
    </div>
  )
}

// MARK: - Multiplayer Root

export function MultiplayerRoot({ onExit }: { onExit: () => void }) {
  const mp = useMultiplayer()
  const { state } = mp
  const { lobbyState } = state

  return (
    <div className="app" style={{ position: 'relative' }}>
      {/* Error toast */}
      {state.errorMessage && (
        <div className="error-toast" onClick={mp.dismissError}>
          {state.errorMessage}
        </div>
      )}

      {lobbyState.kind === 'nameEntry' || lobbyState.kind === 'loading' ? (
        <LobbyView
          displayName={state.displayName}
          joinCode={state.joinCode}
          isLoading={lobbyState.kind === 'loading'}
          onDisplayNameChange={mp.setDisplayName}
          onJoinCodeChange={mp.setJoinCode}
          onCreateRoom={mp.doCreateRoom}
          onJoinRoom={mp.doJoinRoom}
          onExit={onExit}
        />
      ) : lobbyState.kind === 'waitingRoom' ? (
        <WaitingRoomView
          players={state.players}
          currentRoom={state.currentRoom}
          isHost={state.isHost}
          onStartGame={mp.doStartGame}
          onLeave={mp.doLeaveRoom}
        />
      ) : lobbyState.kind === 'playing' || lobbyState.kind === 'roundOver' ? (
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', position: 'relative' }}>
          {state.gameNumbers && (
            <MultiplayerGame
              key={state.gameNumbers.join(',')}
              numbers={state.gameNumbers}
              players={state.players}
              myPlayerId={state.myPlayerId}
              round={state.currentRoom?.round ?? 1}
              totalRounds={state.totalRounds}
              onSubmit={(solutionStr, elapsedSeconds) => {
                mp.doSubmitSolution(solutionStr).then((ok) => {
                  if (ok && state.gameNumbers) {
                    recordSolve(
                      problemKeyFromNumbers(state.gameNumbers),
                      elapsedSeconds,
                      'multiplayer'
                    )
                  }
                })
              }}
              onLeave={mp.doLeaveRoom}
            />
          )}
          {lobbyState.kind === 'roundOver' && (
            <RoundResultOverlay
              winnerName={lobbyState.winnerName}
              didWin={lobbyState.didWin}
            />
          )}
        </div>
      ) : lobbyState.kind === 'dissolved' ? (
        <div className="dissolved-view">
          <p className="dissolved-reason">{lobbyState.reason}</p>
          <button className="mp-action-btn" onClick={mp.dismissError}>
            Back to Menu
          </button>
        </div>
      ) : lobbyState.kind === 'gameOver' ? (
        <GameOverView
          players={state.players}
          myPlayerId={state.myPlayerId}
          isHost={state.isHost}
          onPlayAgain={mp.doPlayAgain}
          onBack={mp.dismissError}
        />
      ) : null}
    </div>
  )
}
