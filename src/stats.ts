import type { Fraction } from './game';

const STORAGE_KEY = 'thosewho24_solves';

export interface SolveRecord {
  problemKey: string;
  elapsedSeconds: number;
  source: 'solo' | 'multiplayer';
  timestamp?: number;
}

export function getSolves(): SolveRecord[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (r): r is SolveRecord =>
        r != null &&
        typeof r === 'object' &&
        typeof (r as SolveRecord).problemKey === 'string' &&
        typeof (r as SolveRecord).elapsedSeconds === 'number' &&
        ((r as SolveRecord).source === 'solo' || (r as SolveRecord).source === 'multiplayer')
    );
  } catch {
    return [];
  }
}

export function recordSolve(
  problemKey: string,
  elapsedSeconds: number,
  source: 'solo' | 'multiplayer'
): void {
  const solves = getSolves();
  solves.push({ problemKey, elapsedSeconds, source, timestamp: Date.now() });
  localStorage.setItem(STORAGE_KEY, JSON.stringify(solves));
}

export interface Stats {
  totalSolves: number;
  uniqueProblems: number;
  averageTimeSeconds: number;
}

export function getStats(): Stats {
  const solves = getSolves();
  if (solves.length === 0) {
    return { totalSolves: 0, uniqueProblems: 0, averageTimeSeconds: 0 };
  }
  const uniqueKeys = new Set(solves.map((r) => r.problemKey));
  const totalTime = solves.reduce((sum, r) => sum + r.elapsedSeconds, 0);
  return {
    totalSolves: solves.length,
    uniqueProblems: uniqueKeys.size,
    averageTimeSeconds: Math.round(totalTime / solves.length),
  };
}

export function problemKeyFromNumbers(numbers: number[]): string {
  return [...numbers].sort((a, b) => a - b).join(',');
}

export function problemKeyFromFractions(fractions: Fraction[]): string {
  return problemKeyFromNumbers(fractions.map((f) => f.num));
}
