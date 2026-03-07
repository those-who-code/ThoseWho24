import { useReducer, useEffect, useRef, useCallback, useMemo } from 'react';
import { Fraction, findAllSolutions } from './game';
import type { NumberCard, MathOperator, Solution } from './game';

// MARK: - State

interface BoardSnapshot {
  cards: NumberCard[];
  message: string;
}

interface GameState {
  cards: NumberCard[];
  selectedCardIndex: number | null;
  selectedOperator: MathOperator | null;
  message: string;
  isGameOver: boolean;
  didWin: boolean;
  showCompleted: boolean;
  showingSolution: boolean;
  revealedStepCount: number;
  elapsedSeconds: number;
  allSolutions: Solution[];
  initialValues: Fraction[];
  undoStack: BoardSnapshot[];
}

// MARK: - Actions

type GameAction =
  | { type: 'NEW_PUZZLE'; values: Fraction[]; solutions: Solution[] }
  | { type: 'SELECT_OPERATOR'; op: MathOperator }
  | { type: 'CARD_TAP'; index: number }
  | { type: 'UNDO' }
  | { type: 'REVEAL_STEP' }
  | { type: 'HIDE_HINTS' }
  | { type: 'TICK' }
  | { type: 'SHOW_COMPLETED' };

// MARK: - Reducer

function makeCards(values: Fraction[]): NumberCard[] {
  return values.map(v => ({ id: crypto.randomUUID(), value: v, isVisible: true }));
}

function gameReducer(state: GameState, action: GameAction): GameState {
  switch (action.type) {
    case 'NEW_PUZZLE':
      return {
        ...state,
        cards: makeCards(action.values),
        selectedCardIndex: null,
        selectedOperator: null,
        message: 'Make 24',
        isGameOver: false,
        didWin: false,
        showCompleted: false,
        showingSolution: false,
        revealedStepCount: 0,
        elapsedSeconds: 0,
        allSolutions: action.solutions,
        initialValues: action.values,
        undoStack: [],
      };

    case 'SELECT_OPERATOR':
      if (state.didWin) return state;
      return { ...state, selectedOperator: action.op };

    case 'CARD_TAP': {
      const { index } = action;
      if (state.didWin || !state.cards[index].isVisible) return state;

      // No card selected yet
      if (state.selectedCardIndex === null) {
        return { ...state, selectedCardIndex: index };
      }

      // Tapped same card — deselect
      if (state.selectedCardIndex === index) {
        return { ...state, selectedCardIndex: null, selectedOperator: null };
      }

      // No operator yet — switch selection
      if (state.selectedOperator === null) {
        return { ...state, selectedCardIndex: index };
      }

      // Compute result
      const val1 = state.cards[state.selectedCardIndex].value;
      const val2 = state.cards[index].value;
      const op = state.selectedOperator;

      let result: Fraction | null;
      if (op === '+') result = val1.add(val2);
      else if (op === '−') result = val1.sub(val2);
      else if (op === '×') result = val1.mul(val2);
      else result = val1.div(val2);

      if (result === null) {
        return {
          ...state,
          message: "Can't divide by zero",
          selectedCardIndex: null,
          selectedOperator: null,
        };
      }

      // Save snapshot for undo
      const snapshot: BoardSnapshot = {
        cards: state.cards.map(c => ({ ...c })),
        message: state.message,
      };

      const newCards = state.cards.map((c, i) => {
        if (i === state.selectedCardIndex) return { ...c, isVisible: false };
        if (i === index) return { ...c, value: result! };
        return c;
      });

      const visible = newCards.filter(c => c.isVisible);
      let message = state.message;
      let isGameOver = false;
      let didWin = false;

      if (visible.length === 1) {
        if (visible[0].value.equals(new Fraction(24))) {
          isGameOver = true;
          didWin = true;
          message = ':)';
        } else {
          message = ':(';
        }
      }

      return {
        ...state,
        cards: newCards,
        selectedCardIndex: index,
        selectedOperator: null,
        message,
        isGameOver,
        didWin,
        undoStack: [...state.undoStack, snapshot],
      };
    }

    case 'UNDO': {
      if (state.undoStack.length === 0 || state.didWin) return state;
      const stack = [...state.undoStack];
      const snapshot = stack.pop()!;
      return {
        ...state,
        cards: snapshot.cards.map(c => ({ ...c })),
        message: snapshot.message,
        selectedCardIndex: null,
        selectedOperator: null,
        isGameOver: false,
        didWin: false,
        undoStack: stack,
      };
    }

    case 'REVEAL_STEP': {
      if (!state.allSolutions.length) return state;
      const maxSteps = state.allSolutions[0].length;
      if (state.revealedStepCount >= maxSteps) return state;
      return { ...state, showingSolution: true, revealedStepCount: state.revealedStepCount + 1 };
    }

    case 'HIDE_HINTS':
      return { ...state, showingSolution: false };

    case 'TICK':
      if (state.isGameOver) return state;
      return { ...state, elapsedSeconds: state.elapsedSeconds + 1 };

    case 'SHOW_COMPLETED':
      return { ...state, showCompleted: true };

    default:
      return state;
  }
}

// MARK: - Multiplayer game hook (no timer, no puzzle gen, driven by provided numbers)

export function useGameWithNumbers(numbers: number[]) {
  const fractions = useMemo(
    () => numbers.map(n => new Fraction(n)),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [numbers.join(',')],
  )
  const solutions = useMemo(() => findAllSolutions(fractions), [fractions])

  const [state, dispatch] = useReducer(gameReducer, {
    cards: makeCards(fractions),
    selectedCardIndex: null,
    selectedOperator: null,
    message: 'Make 24',
    isGameOver: false,
    didWin: false,
    showCompleted: false,
    showingSolution: false,
    revealedStepCount: 0,
    elapsedSeconds: 0,
    allSolutions: solutions,
    initialValues: fractions,
    undoStack: [],
  })

  useEffect(() => {
    const interval = setInterval(() => dispatch({ type: 'TICK' }), 1000)
    return () => clearInterval(interval)
  }, [])

  const canUndo = state.undoStack.length > 0 && !state.didWin
  const solutionFullyRevealed =
    solutions.length === 0 || state.revealedStepCount >= solutions[0].length

  return { ...state, dispatch, canUndo, solutionFullyRevealed }
}

const initialState: GameState = {
  cards: [],
  selectedCardIndex: null,
  selectedOperator: null,
  message: 'Make 24',
  isGameOver: false,
  didWin: false,
  showCompleted: false,
  showingSolution: false,
  revealedStepCount: 0,
  elapsedSeconds: 0,
  allSolutions: [],
  initialValues: [],
  undoStack: [],
};

// MARK: - Hook

export function useGame() {
  const [state, dispatch] = useReducer(gameReducer, initialState);

  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const isGameOverRef = useRef(false);
  isGameOverRef.current = state.isGameOver;

  const stopTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const startTimer = useCallback(() => {
    stopTimer();
    timerRef.current = setInterval(() => {
      if (!isGameOverRef.current) {
        dispatch({ type: 'TICK' });
      }
    }, 1000);
  }, [stopTimer]);

  const generateNewPuzzle = useCallback(() => {
    let values: Fraction[];
    let solutions: Solution[];
    do {
      values = Array.from({ length: 4 }, () => new Fraction(Math.floor(Math.random() * 13) + 1));
      solutions = findAllSolutions(values);
    } while (solutions.length === 0);

    dispatch({ type: 'NEW_PUZZLE', values, solutions });
    startTimer();
  }, [startTimer]);

  // Init
  useEffect(() => {
    generateNewPuzzle();
    return () => stopTimer();
  }, []);

  // Show completed screen 400ms after win
  useEffect(() => {
    if (!state.didWin) return;
    stopTimer();
    const t = setTimeout(() => dispatch({ type: 'SHOW_COMPLETED' }), 400);
    return () => clearTimeout(t);
  }, [state.didWin, stopTimer]);

  const timerString = (() => {
    const m = Math.floor(state.elapsedSeconds / 60);
    const s = state.elapsedSeconds % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  })();

  const solutionFullyRevealed =
    state.allSolutions.length === 0 || state.revealedStepCount >= state.allSolutions[0].length;

  const canUndo = state.undoStack.length > 0 && !state.didWin;

  return {
    ...state,
    timerString,
    solutionFullyRevealed,
    canUndo,
    dispatch,
    generateNewPuzzle,
  };
}
