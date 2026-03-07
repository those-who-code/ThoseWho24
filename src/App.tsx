import { useState, useEffect, useRef } from 'react';
import './App.css';
import { useGame } from './useGame';
import { OPERATORS } from './game';
import type { Fraction, MathOperator, Solution, SolutionStep } from './game';
import { MultiplayerRoot } from './Multiplayer';
import { getStats, getSolves, recordSolve, problemKeyFromFractions } from './stats';
import type { SolveRecord } from './stats';

// MARK: - Fraction Display

function FractionView({ value, selected }: { value: Fraction; selected?: boolean }) {
  if (value.isWhole) {
    return <span className="card-number">{value.num}</span>;
  }
  return (
    <span className={`card-fraction ${selected ? 'card-fraction--selected' : ''}`}>
      <span>{value.num}</span>
      <span className="fraction-divider" />
      <span>{value.den}</span>
    </span>
  );
}

// MARK: - Card

function CardView({
  value,
  isSelected,
  isVisible,
  onClick,
}: {
  value: Fraction;
  isSelected: boolean;
  isVisible: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={`card ${isSelected ? 'card--selected' : ''} ${!isVisible ? 'card--hidden' : ''}`}
      onClick={onClick}
      tabIndex={isVisible ? 0 : -1}
      aria-hidden={!isVisible}
    >
      <FractionView value={value} selected={isSelected} />
    </button>
  );
}

// MARK: - Solution Steps

function SolutionStepsView({ steps }: { steps: SolutionStep[] }) {
  return (
    <div className="solution-steps">
      {steps.map((step, i) => (
        <div key={i} className="solution-step">
          {step.a} {step.op} {step.b} = {step.result}
        </div>
      ))}
    </div>
  );
}

// MARK: - Bottom Button

function BottomButton({
  label,
  icon,
  filled = false,
  disabled = false,
  onClick,
}: {
  label: string;
  icon: string;
  filled?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className={`bottom-btn ${filled ? 'bottom-btn--filled' : ''} ${disabled ? 'bottom-btn--disabled' : ''}`}
      onClick={onClick}
      disabled={disabled}
    >
      <span className="bottom-btn-icon">{icon}</span>
      {label}
    </button>
  );
}

// MARK: - Game View

function GameView({
  timerString,
  cards,
  selectedCardIndex,
  selectedOperator,
  message,
  showingSolution,
  allSolutions,
  revealedStepCount,
  solutionFullyRevealed,
  canUndo,
  onCardTap,
  onSelectOperator,
  onUndo,
  onRevealStep,
  onHideHints,
  onNewPuzzle,
  onMultiplayer,
  onStats,
}: {
  timerString: string;
  cards: ReturnType<typeof useGame>['cards'];
  selectedCardIndex: number | null;
  selectedOperator: MathOperator | null;
  message: string;
  showingSolution: boolean;
  allSolutions: Solution[];
  revealedStepCount: number;
  solutionFullyRevealed: boolean;
  canUndo: boolean;
  onCardTap: (i: number) => void;
  onSelectOperator: (op: MathOperator) => void;
  onUndo: () => void;
  onRevealStep: () => void;
  onHideHints: () => void;
  onNewPuzzle: () => void;
  onMultiplayer: () => void;
  onStats: () => void;
}) {
  const visibleSteps = (allSolutions[0] ?? []).slice(0, revealedStepCount);

  return (
    <div className="game-view">
      {/* Top bar */}
      <div className="top-bar">
        <span className="timer">{timerString}</span>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="mp-nav-btn" onClick={onStats}>
            Stats
          </button>
          <button className="mp-nav-btn" onClick={onMultiplayer}>
            Multiplayer
          </button>
        </div>
        <button
          className={`hint-btn ${solutionFullyRevealed ? 'hint-btn--exhausted' : ''}`}
          onClick={onRevealStep}
          disabled={solutionFullyRevealed}
        >
          {showingSolution && !solutionFullyRevealed ? 'Next hint' : 'Hint'}
        </button>
      </div>

      {/* Message */}
      <p className="game-message">{message}</p>

      {/* Cards or solution steps */}
      {!showingSolution ? (
        <div className="card-grid">
          {cards.map((card, i) => (
            <CardView
              key={card.id}
              value={card.value}
              isSelected={selectedCardIndex === i}
              isVisible={card.isVisible}
              onClick={() => onCardTap(i)}
            />
          ))}
        </div>
      ) : (
        <SolutionStepsView steps={visibleSteps} />
      )}

      {/* Operators */}
      {!showingSolution && (
        <div className="operator-bar">
          {OPERATORS.map(op => (
            <button
              key={op}
              className={`operator-btn ${selectedOperator === op ? 'operator-btn--selected' : ''}`}
              onClick={() => onSelectOperator(op)}
            >
              {op}
            </button>
          ))}
        </div>
      )}

      {/* Bottom buttons */}
      <div className="bottom-buttons">
        {showingSolution ? (
          <BottomButton label="Back" icon="←" onClick={onHideHints} />
        ) : (
          <BottomButton label="Undo" icon="↩" disabled={!canUndo} onClick={onUndo} />
        )}
        <BottomButton label="New Game" icon="→" filled onClick={onNewPuzzle} />
      </div>
    </div>
  );
}

// MARK: - Completed View

function CompletedView({
  timerString,
  allSolutions,
  onNewPuzzle,
  onStats,
}: {
  timerString: string;
  allSolutions: Solution[];
  onNewPuzzle: () => void;
  onStats: () => void;
}) {
  return (
    <div className="completed-view">
      <div className="completed-header">
        <h1 className="completed-title">Solved!</h1>
        <p className="completed-time">{timerString}</p>
      </div>

      <div className="solutions-scroll">
        <p className="solutions-count">
          {allSolutions.length} solution{allSolutions.length === 1 ? '' : 's'} found
        </p>
        {allSolutions.slice(0, 50).map((solution, idx) => (
          <div key={idx} className="solution-card">
            <p className="solution-label">Solution {idx + 1}</p>
            {solution.map((step, si) => (
              <p key={si} className="solution-line">
                {step.a} {step.op} {step.b} = {step.result}
              </p>
            ))}
          </div>
        ))}
      </div>

      <div className="completed-actions">
        <button className="next-game-btn" onClick={onNewPuzzle}>
          Next Game
        </button>
        <button className="stats-link-btn" onClick={onStats}>
          Stats
        </button>
      </div>
    </div>
  );
}

// MARK: - Stats View

function formatAxisTime(seconds: number): string {
  if (seconds === 0) return '0';
  if (seconds < 60) return `${seconds}s`;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return s === 0 ? `${m}m` : `${m}:${s.toString().padStart(2, '0')}`;
}

function formatChartDate(ts: number): string {
  const d = new Date(ts);
  return `${d.getMonth() + 1}/${d.getDate()}`;
}

function niceStep(range: number, targetTicks: number): number {
  const raw = range / targetTicks;
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  return ([1, 2, 5, 10].find(f => f * mag >= raw) ?? 10) * mag;
}

function SolveTimeChart({ solves }: { solves: SolveRecord[] }) {
  type TimedRecord = SolveRecord & { timestamp: number };
  const timed = (solves as TimedRecord[])
    .filter(r => typeof r.timestamp === 'number')
    .sort((a, b) => a.timestamp - b.timestamp);

  if (timed.length < 2) {
    return (
      <div className="chart-empty">
        {timed.length === 0
          ? 'Solve some puzzles to see your progress'
          : 'Solve one more puzzle to see your progress graph'}
      </div>
    );
  }

  const VW = 320, VH = 160;
  const ML = 36, MR = 12, MT = 12, MB = 28;
  const plotW = VW - ML - MR;
  const plotH = VH - MT - MB;

  const maxY = Math.max(...timed.map(r => r.elapsedSeconds));
  const yPad = Math.max(5, Math.ceil(maxY * 0.15));
  const yMax = maxY + yPad;
  const step = niceStep(yMax, 4);
  const yTicks: number[] = [];
  for (let v = 0; v <= yMax; v += step) yTicks.push(v);

  const xOf = (i: number) => ML + (i / (timed.length - 1)) * plotW;
  const yOf = (s: number) => MT + plotH - (s / yMax) * plotH;

  const points = timed.map((r, i) => `${xOf(i)},${yOf(r.elapsedSeconds)}`).join(' ');
  const showDots = timed.length <= 40;

  const labelIdxs = [0, Math.floor((timed.length - 1) / 2), timed.length - 1]
    .filter((v, i, arr) => arr.indexOf(v) === i);

  return (
    <svg viewBox={`0 0 ${VW} ${VH}`} width="100%">
      {yTicks.map(tick => (
        <g key={tick}>
          <line
            x1={ML} x2={VW - MR}
            y1={yOf(tick)} y2={yOf(tick)}
            stroke="rgba(0,0,0,0.07)" strokeWidth="1"
          />
          <text
            x={ML - 4} y={yOf(tick) + 4}
            textAnchor="end" fontSize="9" fill="rgba(0,0,0,0.35)"
          >
            {formatAxisTime(tick)}
          </text>
        </g>
      ))}
      {labelIdxs.map(i => (
        <text
          key={i} x={xOf(i)} y={VH - 4}
          textAnchor="middle" fontSize="9" fill="rgba(0,0,0,0.35)"
        >
          {formatChartDate(timed[i].timestamp)}
        </text>
      ))}
      <polyline
        points={points}
        fill="none"
        stroke="#000"
        strokeWidth="1.5"
        strokeLinejoin="round"
        strokeLinecap="round"
      />
      {showDots && timed.map((r, i) => (
        <circle key={i} cx={xOf(i)} cy={yOf(r.elapsedSeconds)} r="2.5" fill="#000" />
      ))}
    </svg>
  );
}

function formatTime(seconds: number): string {
  if (seconds <= 0) return '0:00';
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function StatsView({ onBack }: { onBack: () => void }) {
  const stats = getStats();
  const solves = getSolves();
  const avgDisplay = stats.totalSolves > 0 ? formatTime(stats.averageTimeSeconds) : '—';

  return (
    <div className="stats-view">
      <div className="top-bar">
        <button className="mp-back-btn" onClick={onBack}>
          ← Back
        </button>
      </div>
      <div className="stats-content">
        <h1 className="stats-title">Stats</h1>
        <div className="stats-grid">
          <div className="stats-card">
            <span className="stats-value">{stats.totalSolves}</span>
            <span className="stats-label">Lifetime solves</span>
          </div>
          <div className="stats-card">
            <span className="stats-value">{stats.uniqueProblems}</span>
            <span className="stats-label">Unique problems solved</span>
          </div>
          <div className="stats-card">
            <span className="stats-value">{avgDisplay}</span>
            <span className="stats-label">Average time per solve</span>
          </div>
        </div>
        <div className="stats-chart-section">
          <p className="stats-section-label">Solve time over time</p>
          <div className="stats-chart-container">
            <SolveTimeChart solves={solves} />
          </div>
        </div>
      </div>
    </div>
  );
}

// MARK: - App Root

export default function App() {
  const game = useGame();
  const [mode, setMode] = useState<'solo' | 'multiplayer' | 'stats'>('solo');
  const recordedCompletionRef = useRef(false);

  useEffect(() => {
    if (!game.showCompleted) recordedCompletionRef.current = false;
  }, [game.showCompleted]);

  useEffect(() => {
    if (
      game.showCompleted &&
      game.initialValues.length === 4 &&
      !recordedCompletionRef.current
    ) {
      recordSolve(
        problemKeyFromFractions(game.initialValues),
        game.elapsedSeconds,
        'solo'
      );
      recordedCompletionRef.current = true;
    }
  }, [game.showCompleted, game.initialValues, game.elapsedSeconds]);

  const handleCardTap = (i: number) => game.dispatch({ type: 'CARD_TAP', index: i });
  const handleSelectOp = (op: MathOperator) => game.dispatch({ type: 'SELECT_OPERATOR', op });
  const handleUndo = () => game.dispatch({ type: 'UNDO' });
  const handleRevealStep = () => game.dispatch({ type: 'REVEAL_STEP' });
  const handleHideHints = () => game.dispatch({ type: 'HIDE_HINTS' });

  if (mode === 'multiplayer') {
    return <MultiplayerRoot onExit={() => setMode('solo')} />;
  }

  if (mode === 'stats') {
    return (
      <div className="app">
        <StatsView onBack={() => setMode('solo')} />
      </div>
    );
  }

  return (
    <div className="app">
      {game.showCompleted ? (
        <CompletedView
          timerString={game.timerString}
          allSolutions={game.allSolutions}
          onNewPuzzle={game.generateNewPuzzle}
          onStats={() => setMode('stats')}
        />
      ) : (
        <GameView
          timerString={game.timerString}
          cards={game.cards}
          selectedCardIndex={game.selectedCardIndex}
          selectedOperator={game.selectedOperator}
          message={game.message}
          showingSolution={game.showingSolution}
          allSolutions={game.allSolutions}
          revealedStepCount={game.revealedStepCount}
          solutionFullyRevealed={game.solutionFullyRevealed}
          canUndo={game.canUndo}
          onCardTap={handleCardTap}
          onSelectOperator={handleSelectOp}
          onUndo={handleUndo}
          onRevealStep={handleRevealStep}
          onHideHints={handleHideHints}
          onNewPuzzle={game.generateNewPuzzle}
          onMultiplayer={() => setMode('multiplayer')}
          onStats={() => setMode('stats')}
        />
      )}
    </div>
  );
}
