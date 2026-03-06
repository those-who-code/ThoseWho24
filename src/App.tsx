import { useState } from 'react';
import './App.css';
import { useGame } from './useGame';
import { OPERATORS } from './game';
import type { Fraction, MathOperator, Solution, SolutionStep } from './game';
import { MultiplayerRoot } from './Multiplayer';

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
}) {
  const visibleSteps = (allSolutions[0] ?? []).slice(0, revealedStepCount);

  return (
    <div className="game-view">
      {/* Top bar */}
      <div className="top-bar">
        <span className="timer">{timerString}</span>
        <button className="mp-nav-btn" onClick={onMultiplayer}>
          Multiplayer
        </button>
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
}: {
  timerString: string;
  allSolutions: Solution[];
  onNewPuzzle: () => void;
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

      <button className="next-game-btn" onClick={onNewPuzzle}>
        Next Game
      </button>
    </div>
  );
}

// MARK: - App Root

export default function App() {
  const game = useGame();
  const [mode, setMode] = useState<'solo' | 'multiplayer'>('solo');

  const handleCardTap = (i: number) => game.dispatch({ type: 'CARD_TAP', index: i });
  const handleSelectOp = (op: MathOperator) => game.dispatch({ type: 'SELECT_OPERATOR', op });
  const handleUndo = () => game.dispatch({ type: 'UNDO' });
  const handleRevealStep = () => game.dispatch({ type: 'REVEAL_STEP' });
  const handleHideHints = () => game.dispatch({ type: 'HIDE_HINTS' });

  if (mode === 'multiplayer') {
    return <MultiplayerRoot onExit={() => setMode('solo')} />;
  }

  return (
    <div className="app">
      {game.showCompleted ? (
        <CompletedView
          timerString={game.timerString}
          allSolutions={game.allSolutions}
          onNewPuzzle={game.generateNewPuzzle}
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
        />
      )}
    </div>
  );
}
