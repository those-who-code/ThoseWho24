// MARK: - Fraction

export class Fraction {
  readonly num: number;
  readonly den: number;

  constructor(num: number, den: number = 1) {
    if (den === 0) {
      this.num = num;
      this.den = 1;
    } else {
      const g = Fraction.gcd(Math.abs(num), Math.abs(den));
      const sign = den < 0 ? -1 : 1;
      this.num = (sign * num) / g;
      this.den = (sign * den) / g;
    }
  }

  static gcd(a: number, b: number): number {
    return b === 0 ? a : Fraction.gcd(b, a % b);
  }

  get isWhole(): boolean {
    return this.den === 1;
  }

  get display(): string {
    return this.den === 1 ? `${this.num}` : `${this.num}/${this.den}`;
  }

  equals(other: Fraction): boolean {
    return this.num === other.num && this.den === other.den;
  }

  add(other: Fraction): Fraction {
    return new Fraction(this.num * other.den + other.num * this.den, this.den * other.den);
  }

  sub(other: Fraction): Fraction {
    return new Fraction(this.num * other.den - other.num * this.den, this.den * other.den);
  }

  mul(other: Fraction): Fraction {
    return new Fraction(this.num * other.num, this.den * other.den);
  }

  div(other: Fraction): Fraction | null {
    if (other.num === 0) return null;
    return new Fraction(this.num * other.den, this.den * other.num);
  }
}

// MARK: - Types

export interface SolutionStep {
  a: string;
  op: string;
  b: string;
  result: string;
}

export type Solution = SolutionStep[];

export interface NumberCard {
  id: string;
  value: Fraction;
  isVisible: boolean;
}

export type MathOperator = '+' | '−' | '×' | '÷';
export const OPERATORS: MathOperator[] = ['+', '−', '×', '÷'];

// MARK: - Solver

export function findAllSolutions(values: Fraction[]): Solution[] {
  const results: Solution[] = [];
  const seen = new Set<string>();

  function solve(numbers: Fraction[], labels: string[], steps: SolutionStep[]) {
    if (numbers.length === 1) {
      if (numbers[0].equals(new Fraction(24))) {
        const key = steps.map(s => `${s.a}${s.op}${s.b}`).join('|');
        if (!seen.has(key)) {
          seen.add(key);
          results.push([...steps]);
        }
      }
      return;
    }

    const ops: [string, (a: Fraction, b: Fraction) => Fraction | null][] = [
      ['+', (a, b) => a.add(b)],
      ['−', (a, b) => a.sub(b)],
      ['×', (a, b) => a.mul(b)],
      ['÷', (a, b) => a.div(b)],
    ];

    for (let i = 0; i < numbers.length; i++) {
      for (let j = 0; j < numbers.length; j++) {
        if (i === j) continue;
        for (const [symbol, op] of ops) {
          const res = op(numbers[i], numbers[j]);
          if (res === null || res.num < 0) continue;

          const nextNumbers = numbers.filter((_, k) => k !== i && k !== j).concat(res);
          const nextLabels = labels
            .filter((_, k) => k !== i && k !== j)
            .concat(`(${labels[i]} ${symbol} ${labels[j]})`);

          solve(nextNumbers, nextLabels, [
            ...steps,
            { a: labels[i], op: symbol, b: labels[j], result: res.display },
          ]);
        }
      }
    }
  }

  solve(values, values.map(v => v.display), []);
  return results;
}
