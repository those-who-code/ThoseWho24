import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

enum Haptics {
    static func light() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    static func medium() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
    static func heavy() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
    }
    static func successDoubleTap() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            generator.impactOccurred()
        }
        #endif
    }
    static func extendedError() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }
    static func selection() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

// MARK: - Fraction Type

struct Fraction: Equatable, Hashable {
    let num: Int
    let den: Int

    init(_ num: Int, _ den: Int = 1) {
        if den == 0 {
            self.num = num
            self.den = 1
        } else {
            let g = Fraction.gcd(abs(num), abs(den))
            let sign = den < 0 ? -1 : 1
            self.num = sign * num / g
            self.den = sign * den / g
        }
    }

    init(from double: Double) {
        if double == double.rounded() {
            self.init(Int(double), 1)
        } else {
            let precision = 10000
            let n = Int(round(double * Double(precision)))
            self.init(n, precision)
        }
    }

    var doubleValue: Double { Double(num) / Double(den) }
    var isWhole: Bool { den == 1 }

    var display: String {
        if den == 1 { return "\(num)" }
        return "\(num)/\(den)"
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    static func + (l: Fraction, r: Fraction) -> Fraction {
        Fraction(l.num * r.den + r.num * l.den, l.den * r.den)
    }
    static func - (l: Fraction, r: Fraction) -> Fraction {
        Fraction(l.num * r.den - r.num * l.den, l.den * r.den)
    }
    static func * (l: Fraction, r: Fraction) -> Fraction {
        Fraction(l.num * r.num, l.den * r.den)
    }
    static func / (l: Fraction, r: Fraction) -> Fraction? {
        if r.num == 0 { return nil }
        return Fraction(l.num * r.den, l.den * r.num)
    }
}

// MARK: - Models

struct NumberCard: Identifiable {
    let id = UUID()
    var value: Fraction
    var isVisible: Bool = true
}

enum MathOperator: String, CaseIterable {
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
}

// MARK: - Solution Finder

struct SolutionStep: Hashable {
    let a: String
    let op: String
    let b: String
    let result: String
}

struct Solution {
    let expression: String   // full expression, e.g. "8 × (6 − (8 − 5))"
    let steps: [SolutionStep]
}

struct PlayerMove {
    let firstIdx: Int   // card index that was consumed
    let secondIdx: Int  // card index that received the result
    let op: String      // operator raw value: "+", "−", "×", "÷"
    let aLabel: String
    let bLabel: String
    let resultLabel: String
}

// Canonical expression tree.
// + and × are commutative+associative (chains are flattened and sorted).
// − is treated as addition with a negated sign (a−b flattens into the same signed pool as a+b).
// ÷ is treated as multiplication with an inverted power (a÷b flattens into the same product pool).
// After each combination, identity elements (×1, ÷1, +0, −0) and inverse pairs (a−a, a÷a)
// are eliminated so that no-op steps don't produce redundant solutions.
private indirect enum CanonExpr {
    case leaf(String)
    case sum([(CanonExpr, Bool)])      // (sub, isPositive), sorted by key+sign
    case product([(CanonExpr, Bool)])  // (sub, isNumerator), sorted by key+power

    var key: String {
        switch self {
        case .leaf(let s): return s
        case .sum(let terms):
            return "S:" + terms.map { ($0.1 ? "+" : "-") + $0.0.key }.joined(separator: "|")
        case .product(let factors):
            return "P:" + factors.map { ($0.1 ? "*" : "/") + $0.0.key }.joined(separator: "|")
        }
    }

    func sumTerms(positive: Bool) -> [(CanonExpr, Bool)] {
        if case .sum(let t) = self { return positive ? t : t.map { ($0.0, !$0.1) } }
        return [(self, positive)]
    }

    func productFactors(numerator: Bool) -> [(CanonExpr, Bool)] {
        if case .product(let f) = self { return numerator ? f : f.map { ($0.0, !$0.1) } }
        return [(self, numerator)]
    }

    static func combine(_ a: CanonExpr, op: String, _ b: CanonExpr) -> CanonExpr {
        switch op {
        case "+":
            var t = a.sumTerms(positive: true) + b.sumTerms(positive: true)
            t.sort { $0.0.key + ($0.1 ? "+" : "-") < $1.0.key + ($1.1 ? "+" : "-") }
            return simplifiedSum(t)
        case "−":
            var t = a.sumTerms(positive: true) + b.sumTerms(positive: false)
            t.sort { $0.0.key + ($0.1 ? "+" : "-") < $1.0.key + ($1.1 ? "+" : "-") }
            return simplifiedSum(t)
        case "×":
            var f = a.productFactors(numerator: true) + b.productFactors(numerator: true)
            f.sort { $0.0.key + ($0.1 ? "*" : "/") < $1.0.key + ($1.1 ? "*" : "/") }
            return simplifiedProduct(f)
        case "÷":
            var f = a.productFactors(numerator: true) + b.productFactors(numerator: false)
            f.sort { $0.0.key + ($0.1 ? "*" : "/") < $1.0.key + ($1.1 ? "*" : "/") }
            return simplifiedProduct(f)
        default: return a
        }
    }

    // Cancel (e,+)/(e,−) pairs, then drop leaf("0") additive identities.
    private static func simplifiedSum(_ terms: [(CanonExpr, Bool)]) -> CanonExpr {
        var t = terms
        var i = 0
        while i < t.count {
            if let j = t.indices.dropFirst(i + 1).first(where: {
                t[$0].0.key == t[i].0.key && t[$0].1 != t[i].1
            }) { t.remove(at: j); t.remove(at: i) } else { i += 1 }
        }
        t.removeAll { item in
            if case .leaf(let s) = item.0 { return s == "0" }
            return false
        }
        if t.isEmpty { return .leaf("0") }
        if t.count == 1, t[0].1 { return t[0].0 }
        return .sum(t)
    }

    // Cancel (e,num)/(e,den) pairs, then drop leaf("1") multiplicative identities.
    private static func simplifiedProduct(_ factors: [(CanonExpr, Bool)]) -> CanonExpr {
        var f = factors
        var i = 0
        while i < f.count {
            if let j = f.indices.dropFirst(i + 1).first(where: {
                f[$0].0.key == f[i].0.key && f[$0].1 != f[i].1
            }) { f.remove(at: j); f.remove(at: i) } else { i += 1 }
        }
        f.removeAll { item in
            if case .leaf(let s) = item.0 { return s == "1" }
            return false
        }
        if f.isEmpty { return .leaf("1") }
        if f.count == 1, f[0].1 { return f[0].0 }
        return .product(f)
    }
}

private func stripOuterParens(_ s: String) -> String {
    guard s.hasPrefix("("), s.hasSuffix(")") else { return s }
    var depth = 0
    for (i, c) in s.enumerated() {
        if c == "(" { depth += 1 }
        else if c == ")" {
            depth -= 1
            if depth == 0 { return i == s.count - 1 ? String(s.dropFirst().dropLast()) : s }
        }
    }
    return s
}

// Score a step sequence: prefer fewer fractional intermediates, then smaller max value.
// Lower is better.
private func solutionScore(_ steps: [SolutionStep]) -> (Int, Int) {
    let fractions = steps.filter { $0.result.contains("/") }.count
    let maxMag = steps.flatMap { [$0.a, $0.b, $0.result] }.reduce(0) { acc, s in
        let parts = s.split(separator: "/")
        return max(acc, abs(Int(parts.first ?? "") ?? 0))
    }
    return (fractions, maxMag)
}

func findAllSolutions(values: [Fraction]) -> [Solution] {
    // keyed by CanonExpr.key; value is (score, solution) for the best representative found so far
    var best: [String: ((Int, Int), Solution)] = [:]
    var order: [String] = []  // keys in first-seen order, for stable display ordering

    func solve(numbers: [Fraction], labels: [String], canons: [CanonExpr], steps: [SolutionStep]) {
        if numbers.count == 1 {
            if numbers[0] == Fraction(24) {
                let key = canons[0].key
                let sol = Solution(expression: stripOuterParens(labels[0]), steps: steps)
                let score = solutionScore(steps)
                if let (prevScore, _) = best[key] {
                    // Replace if this path has fewer fractions or smaller max value
                    if score < prevScore { best[key] = (score, sol) }
                } else {
                    order.append(key)
                    best[key] = (score, sol)
                }
            }
            return
        }

        let ops: [(String, (Fraction, Fraction) -> Fraction?)] = [
            ("+", { a, b in a + b }),
            ("−", { a, b in a - b }),
            ("×", { a, b in a * b }),
            ("÷", { a, b in a / b })
        ]

        for i in 0..<numbers.count {
            for j in 0..<numbers.count where j != i {
                for (symbol, op) in ops {
                    guard let res = op(numbers[i], numbers[j]) else { continue }
                    if res.num < 0 { continue }

                    var nextNumbers: [Fraction] = []
                    var nextLabels: [String] = []
                    var nextCanons: [CanonExpr] = []
                    for k in 0..<numbers.count where k != i && k != j {
                        nextNumbers.append(numbers[k])
                        nextLabels.append(labels[k])
                        nextCanons.append(canons[k])
                    }

                    nextNumbers.append(res)
                    nextLabels.append("(\(labels[i]) \(symbol) \(labels[j]))")
                    nextCanons.append(.combine(canons[i], op: symbol, canons[j]))

                    // Steps show numeric values of operands (not expression strings)
                    let step = SolutionStep(
                        a: numbers[i].display, op: symbol, b: numbers[j].display, result: res.display
                    )

                    solve(numbers: nextNumbers, labels: nextLabels, canons: nextCanons, steps: steps + [step])
                }
            }
        }
    }

    let labels = values.map { $0.display }
    let canons = labels.map { CanonExpr.leaf($0) }
    solve(numbers: values, labels: labels, canons: canons, steps: [])
    return order.compactMap { best[$0]?.1 }
}

// MARK: - Board Snapshot for Undo

struct BoardSnapshot {
    let cards: [NumberCard]
    let message: String
}

// MARK: - ViewModel

class GameViewModel: ObservableObject {
    @Published var cards: [NumberCard] = []
    @Published var selectedCardIndex: Int? = nil
    @Published var selectedOperator: MathOperator? = nil
    @Published var message: String = "Make 24"
    @Published var isGameOver: Bool = false
    @Published var didWin: Bool = false
    @Published var showCompleted: Bool = false
    @Published var showingSolution: Bool = false
    @Published var revealedStepCount: Int = 0
    @Published var elapsedSeconds: Int = 0

    private var initialValues: [Fraction] = []
    private var timerCancellable: AnyCancellable?
    private var startTime: Date?
    private var dailyStartedAt: Date?
    private var undoStack: [BoardSnapshot] = []
    var allSolutions: [Solution] = []
    var playerMoves: [PlayerMove] = []
    var isMultiplayer = false
    var isDailyPuzzle = false
    var onDailySolve: ((Double) -> Void)?

    var canUndo: Bool { !undoStack.isEmpty && !didWin }

    init() {
        generateNewPuzzle()
    }

    // Used by multiplayer to set a server-provided puzzle
    func setupMultiplayerRound(numbers: [Int]) {
        isMultiplayer = true
        isDailyPuzzle = false
        let fractions = numbers.map { Fraction($0) }
        initialValues = fractions
        allSolutions = findAllSolutions(values: fractions)
        showCompleted = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        playerMoves = []
        isGameOver = false
        didWin = false
        selectedCardIndex = nil
        selectedOperator = nil
        cards = fractions.map { NumberCard(value: $0) }
        message = "Make 24"
        stopTimer()
    }

    func setupDailyPuzzle(
        numbers: [Int],
        startedAt: Date,
        onSolve: @escaping (Double) -> Void
    ) {
        isMultiplayer = false
        isDailyPuzzle = true
        dailyStartedAt = startedAt
        onDailySolve = onSolve
        let fractions = numbers.map { Fraction($0) }
        initialValues = fractions
        allSolutions = findAllSolutions(values: fractions)
        showCompleted = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        playerMoves = []
        resetBoard(startedAt: startedAt)
    }

    func hideHints() {
        showingSolution = false
    }

    func generateNewPuzzle() {
        var newValues: [Fraction] = []
        repeat {
            newValues = (0..<4).map { _ in Fraction(Int.random(in: 1...13)) }
        } while findAllSolutions(values: newValues).isEmpty

        initialValues = newValues
        allSolutions = findAllSolutions(values: newValues)
        showCompleted = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        resetBoard()
    }

    func resetBoard(startedAt: Date? = nil) {
        cards = initialValues.map { NumberCard(value: $0) }
        selectedCardIndex = nil
        selectedOperator = nil
        message = "Make 24"
        isGameOver = false
        didWin = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        playerMoves = []
        startTimer(startedAt: startedAt ?? (isDailyPuzzle ? dailyStartedAt : nil))
    }

    func startTimer(startedAt: Date? = nil) {
        let effectiveStart = startedAt ?? Date()
        startTime = effectiveStart
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(effectiveStart)))
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isGameOver else { return }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(effectiveStart)))
            }
    }

    func stopTimer() {
        timerCancellable?.cancel()
    }

    var timerString: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private func saveSnapshot() {
        let snapshot = BoardSnapshot(
            cards: cards.map { NumberCard(value: $0.value, isVisible: $0.isVisible) },
            message: message
        )
        undoStack.append(snapshot)
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        for i in 0..<cards.count {
            cards[i].value = snapshot.cards[i].value
            cards[i].isVisible = snapshot.cards[i].isVisible
        }
        message = snapshot.message
        selectedCardIndex = nil
        selectedOperator = nil
        isGameOver = false
        didWin = false
        if !playerMoves.isEmpty { playerMoves.removeLast() }
    }

    func handleCardTap(at index: Int) {
        guard !didWin, cards[index].isVisible else { return }

        if selectedCardIndex == nil {
            selectedCardIndex = index
            return
        }

        if selectedCardIndex == index {
            selectedCardIndex = nil
            selectedOperator = nil
            return
        }

        guard let op = selectedOperator, let firstIndex = selectedCardIndex else {
            selectedCardIndex = index
            return
        }

        let val1 = cards[firstIndex].value
        let val2 = cards[index].value
        var result: Fraction

        switch op {
        case .add:      result = val1 + val2
        case .subtract: result = val1 - val2
        case .multiply: result = val1 * val2
        case .divide:
            guard let div = val1 / val2 else {
                message = "Can't divide by zero"
                selectedCardIndex = nil
                selectedOperator = nil
                Haptics.extendedError()
                return
            }
            result = div
        }

        saveSnapshot()
        playerMoves.append(PlayerMove(
            firstIdx: firstIndex, secondIdx: index, op: op.rawValue,
            aLabel: formatValue(val1), bLabel: formatValue(val2), resultLabel: formatValue(result)
        ))

        cards[firstIndex].isVisible = false
        cards[index].value = result

        selectedCardIndex = index
        selectedOperator = nil

        checkWinCondition()
    }

    private func checkWinCondition() {
        let visibleCards = cards.filter { $0.isVisible }

        if visibleCards.count == 1 {
            if visibleCards[0].value == Fraction(24) {
                isGameOver = true
                didWin = true
                stopTimer()
                message = ":)"
                if !isMultiplayer {
                    let solveSeconds = startTime.map { Date().timeIntervalSince($0) } ?? Double(elapsedSeconds)
                    StatsManager.shared.recordSolve(seconds: solveSeconds, numbers: initialValues.map { $0.num })
                    Haptics.successDoubleTap()
                    if isDailyPuzzle {
                        onDailySolve?(solveSeconds)
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation { self.showCompleted = true }
                        }
                    }
                } else {
                    Haptics.successDoubleTap()
                }
            } else {
                message = ":("
                Haptics.extendedError()
            }
        }
    }
    
    func revealNextStep() {
        guard let solution = allSolutions.first else { return }
        if revealedStepCount < solution.steps.count {
            showingSolution = true
            revealedStepCount += 1
        }
    }

    var solutionFullyRevealed: Bool {
        guard let solution = allSolutions.first else { return true }
        return revealedStepCount >= solution.steps.count
    }

    func formatValue(_ value: Fraction) -> String {
        value.display
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = GameViewModel()
    @ObservedObject private var themeManager = ThemeManager.shared
    var onMultiplayerTap: (() -> Void)? = nil
    var onStatsTap: (() -> Void)? = nil
    var onSettingsTap: (() -> Void)? = nil
    var onDailyTap: (() -> Void)? = nil
    var highlightDailyBanner = false
    var isOnline = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if vm.showCompleted {
                CompletedView(vm: vm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                GameView(
                    vm: vm,
                    onMultiplayerTap: onMultiplayerTap,
                    onStatsTap: onStatsTap,
                    onSettingsTap: onSettingsTap,
                    onDailyTap: onDailyTap,
                    highlightDailyBanner: highlightDailyBanner,
                    isOnline: isOnline
                )
            }
        }
    }
}

// MARK: - Fraction Display View

struct FractionView: View {
    let fraction: Fraction
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        if fraction.isWhole {
            Text("\(fraction.num)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(color)
        } else {
            VStack(spacing: 1) {
                Text("\(fraction.num)")
                    .font(.system(size: fontSize * 0.55, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(height: 2)
                    .frame(maxWidth: fontSize * 1.8)
                Text("\(fraction.den)")
                    .font(.system(size: fontSize * 0.55, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Game View

struct GameView: View {
    @ObservedObject var vm: GameViewModel
    var onMultiplayerTap: (() -> Void)? = nil
    var onStatsTap: (() -> Void)? = nil
    var onSettingsTap: (() -> Void)? = nil
    var onDailyTap: (() -> Void)? = nil
    var highlightDailyBanner = false
    var isOnline = true
    var isDailyPuzzle = false
    var onDailyExit: (() -> Void)? = nil
    @State private var dailyBannerPulse = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 13, weight: .medium))
                    Text(vm.timerString)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Theme.cream.opacity(0.7))
                .clipShape(Capsule())

                Spacer()

                if isDailyPuzzle, let onDailyExit {
                    Button {
                        Haptics.light()
                        onDailyExit()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.cream.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else if let onSettingsTap {
                    Button {
                        Haptics.light()
                        onSettingsTap()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.cream.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let onStatsTap {
                    Button {
                        Haptics.light()
                        onStatsTap()
                    } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.cream.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let onMultiplayerTap {
                    Button {
                        Haptics.light()
                        onMultiplayerTap()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Multiplayer")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.cream.opacity(0.7))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(isOnline ? 1 : 0.5)
                    .accessibilityHint(isOnline ? "Create or join an online room" : "Internet connection required")
                    Spacer()
                }

                if !isDailyPuzzle {
                    Button {
                        Haptics.light()
                        vm.revealNextStep()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 16, weight: .medium))
                            if vm.showingSolution && !vm.solutionFullyRevealed {
                                Text("Next")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                        .foregroundColor(vm.solutionFullyRevealed ? Theme.amber.opacity(0.3) : Theme.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.cream.opacity(0.7))
                        .clipShape(Capsule())
                    }
                    .disabled(vm.solutionFullyRevealed)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            if !isDailyPuzzle, let onDailyTap {
                Button {
                    Haptics.light()
                    onDailyTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.amber)
                        Text("Daily Puzzle")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.brown)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Theme.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(Theme.cream)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                Theme.amber.opacity(
                                    highlightDailyBanner && dailyBannerPulse ? 0.85 : 0.25
                                ),
                                lineWidth: highlightDailyBanner ? 2 : 1
                            )
                    )
                    .shadow(
                        color: Theme.amber.opacity(
                            highlightDailyBanner && dailyBannerPulse ? 0.35 : 0
                        ),
                        radius: 8
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isOnline)
                .opacity(isOnline ? 1 : 0.5)
                .scaleEffect(highlightDailyBanner && dailyBannerPulse ? 1.045 : 1)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    guard highlightDailyBanner else { return }
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                        dailyBannerPulse = true
                    }
                }

                Spacer()
            }

            // Title
            Text(vm.message)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
                .padding(.bottom, 32)

            // Cards 2x2
            if !vm.showingSolution {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(vm.cards.enumerated()), id: \.element.id) { index, card in
                        MinimalCardView(
                            fraction: card.value,
                            isSelected: vm.selectedCardIndex == index,
                            isVisible: card.isVisible,
                            colorIndex: index
                        )
                        .onTapGesture {
                            Haptics.selection()
                            vm.handleCardTap(at: index)
                        }
                    }
                }
                .padding(.horizontal, 32)
            } else {
                // Show revealed steps (last step first)
                SolutionStepsView(
                    solution: vm.allSolutions.first?.steps ?? [],
                    revealedCount: vm.revealedStepCount
                )
                .padding(.horizontal, 32)
            }

            Spacer()

            // Operators
            if !vm.showingSolution {
                HStack(spacing: 4) {
                    ForEach(MathOperator.allCases, id: \.self) { op in
                        Button {
                            Haptics.light()
                            vm.selectedOperator = vm.selectedOperator == op ? nil : op
                        } label: {
                            Text(op.rawValue)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundColor(vm.selectedOperator == op ? Theme.cardSelectedText : Theme.brown)
                                .background(
                                    vm.selectedOperator == op
                                        ? Theme.operatorSelected
                                        : Theme.operatorBg
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Theme.cream.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 32)
            }

            // Bottom buttons
            HStack(spacing: 12) {
                if vm.showingSolution {
                    BottomButton(label: "Back", icon: "arrow.left") {
                        Haptics.medium()
                        vm.hideHints()
                    }
                } else {
                    BottomButton(label: "Undo", icon: "arrow.uturn.backward", enabled: vm.canUndo) {
                        Haptics.medium()
                        vm.undo()
                    }
                }
                if isDailyPuzzle {
                    BottomButton(label: "Start Over", icon: "arrow.counterclockwise", filled: true) {
                        Haptics.heavy()
                        vm.resetBoard()
                    }
                } else {
                    BottomButton(label: "New Game", icon: "arrow.right", filled: true) {
                        Haptics.heavy()
                        vm.generateNewPuzzle()
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Completed View

struct CompletedView: View {
    @ObservedObject var vm: GameViewModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Solved!")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
                .padding(.bottom, 4)

            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .medium))
                Text(vm.timerString)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.cream.opacity(0.7))
            .clipShape(Capsule())
            .padding(.bottom, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(vm.allSolutions.count) solution\(vm.allSolutions.count == 1 ? "" : "s") found")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 32)

                    ForEach(Array(vm.allSolutions.prefix(50).enumerated()), id: \.offset) { idx, sol in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Solution \(idx + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.textPrimary)

                            Text(sol.expression)
                                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.brown)

                            ForEach(Array(sol.steps.enumerated()), id: \.offset) { _, step in
                                Text("\(step.a) \(step.op) \(step.b) = \(step.result)")
                                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 32)
                    }
                }
            }

            Spacer()

            Button {
                Haptics.heavy()
                vm.generateNewPuzzle()
            } label: {
                HStack(spacing: 6) {
                    Text("Next Game")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Theme.buttonPrimary)
                .foregroundColor(Theme.cardSelectedText)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Subviews

struct MinimalCardView: View {
    let fraction: Fraction
    let isSelected: Bool
    let isVisible: Bool
    var colorIndex: Int = 0

    private var cardBg: Color {
        if isSelected { return Theme.cardSelected }
        return Theme.cardColors[colorIndex % Theme.cardColors.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(cardBg)
                .shadow(color: Theme.brown.opacity(isSelected ? 0.25 : 0.08), radius: isSelected ? 8 : 4, y: isSelected ? 4 : 2)

            FractionView(
                fraction: fraction,
                fontSize: 36,
                color: isSelected ? Theme.cardSelectedText : Theme.brown
            )
        }
        .frame(height: 110)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.85)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isVisible)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

struct SolutionStepsView: View {
    let solution: [SolutionStep]
    let revealedCount: Int

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(solution.enumerated()), id: \.offset) { idx, step in
                let isRevealed = idx >= solution.count - revealedCount
                Group {
                    if isRevealed {
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.accentText)
                                .frame(width: 24, height: 24)
                                .background(Theme.amber)
                                .clipShape(Circle())

                            Text("\(step.a) \(step.op) \(step.b) = \(step.result)")
                                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.amber.opacity(0.25))
                                .frame(width: 24, height: 24)

                            Capsule()
                                .fill(Theme.brown.opacity(0.12))
                                .frame(height: 18)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: revealedCount)
    }
}

struct BottomButton: View {
    let label: String
    let icon: String
    var filled: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(filled ? Theme.buttonPrimary : Theme.buttonSecondary.opacity(enabled ? 1 : 0.5))
            .foregroundColor(
                filled ? Theme.cardSelectedText : (enabled ? Theme.textPrimary : Theme.textMuted)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Theme.brown.opacity(filled ? 0.15 : 0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
