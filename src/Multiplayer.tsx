import { useState } from 'react'
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
  onSubmit,
  onLeave,
}: {
  numbers: number[]
  players: PlayerRow[]
  myPlayerId: string | null
  round: number
  onSubmit: (solutionStr: string, elapsedSeconds: number) => void
  onLeave: () => void
}) {
  const game = useGameWithNumbers(numbers)

  const handleCardTap = (i: number) => game.dispatch({ type: 'CARD_TAP', index: i })
  const handleSelectOp = (op: MathOperator) => game.dispatch({ type: 'SELECT_OPERATOR', op })
  const handleUndo = () => game.dispatch({ type: 'UNDO' })

  const handleSubmit = () => {
    if (!game.didWin) return
    const solutionStr =
      game.allSolutions[0]
        ?.map(s => `${s.a} ${s.op} ${s.b} = ${s.result}`)
        .join(', ') ?? 'solved'
    onSubmit(solutionStr, game.elapsedSeconds)
  }

  return (
    <div className="game-view">
      {/* Top bar */}
      <div className="top-bar">
        <button className="mp-back-btn" onClick={onLeave}>← Leave</button>
        <span className="mp-round-label">Round {round}</span>
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
        <button
          className={`bottom-btn bottom-btn--filled ${!game.didWin ? 'bottom-btn--disabled' : ''}`}
          onClick={handleSubmit}
          disabled={!game.didWin}
        >
          <span className="bottom-btn-icon">✓</span> Submit
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
  onStartGame: () => void
  onLeave: () => void
}) {
  const [copied, setCopied] = useState(false)

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

      <div style={{ padding: '0 32px 40px' }}>
        {isHost ? (
          <button
            className={`mp-action-btn ${players.length < 2 ? 'mp-action-btn--disabled' : ''}`}
            onClick={onStartGame}
            disabled={players.length < 2}
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
      ) : null}
    </div>
  )
}
