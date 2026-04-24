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

typealias Solution = [SolutionStep]

func findAllSolutions(values: [Fraction]) -> [Solution] {
    var results: [Solution] = []
    var seen: Set<String> = []

    func solve(numbers: [Fraction], labels: [String], steps: [SolutionStep]) {
        if numbers.count == 1 {
            if numbers[0] == Fraction(24) {
                let key = steps.map { "\($0.a)\($0.op)\($0.b)" }.joined(separator: "|")
                if !seen.contains(key) {
                    seen.insert(key)
                    results.append(steps)
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
                    for k in 0..<numbers.count where k != i && k != j {
                        nextNumbers.append(numbers[k])
                        nextLabels.append(labels[k])
                    }

                    let resLabel = "(\(labels[i]) \(symbol) \(labels[j]))"
                    nextNumbers.append(res)
                    nextLabels.append(resLabel)

                    let step = SolutionStep(
                        a: labels[i], op: symbol, b: labels[j], result: res.display
                    )

                    solve(numbers: nextNumbers, labels: nextLabels, steps: steps + [step])
                }
            }
        }
    }

    let labels = values.map { $0.display }
    solve(numbers: values, labels: labels, steps: [])
    return results
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
    private var undoStack: [BoardSnapshot] = []
    var allSolutions: [Solution] = []

    var canUndo: Bool { !undoStack.isEmpty && !didWin }

    init() {
        generateNewPuzzle()
    }

    // Used by multiplayer to set a server-provided puzzle
    func setupMultiplayerRound(numbers: [Int]) {
        let fractions = numbers.map { Fraction($0) }
        initialValues = fractions
        allSolutions = findAllSolutions(values: fractions)
        showCompleted = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        isGameOver = false
        didWin = false
        selectedCardIndex = nil
        selectedOperator = nil
        cards = fractions.map { NumberCard(value: $0) }
        message = "Make 24"
        stopTimer()
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

    func resetBoard() {
        cards = initialValues.map { NumberCard(value: $0) }
        selectedCardIndex = nil
        selectedOperator = nil
        message = "Make 24"
        isGameOver = false
        didWin = false
        showingSolution = false
        revealedStepCount = 0
        undoStack = []
        startTimer()
    }

    func startTimer() {
        elapsedSeconds = 0
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isGameOver else { return }
                self.elapsedSeconds += 1
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
                Haptics.successDoubleTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAnimation { self.showCompleted = true }
                }
            } else {
                message = ":("
                Haptics.extendedError()
            }
        }
    }
    
    func revealNextStep() {
        guard let solution = allSolutions.first else { return }
        if revealedStepCount < solution.count {
            showingSolution = true
            revealedStepCount += 1
        }
    }

    var solutionFullyRevealed: Bool {
        guard let solution = allSolutions.first else { return true }
        return revealedStepCount >= solution.count
    }

    func formatValue(_ value: Fraction) -> String {
        value.display
    }
}

// MARK: - Main View

struct ContentView: View {
    @StateObject private var vm = GameViewModel()
    var onMultiplayerTap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if vm.showCompleted {
                CompletedView(vm: vm)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                GameView(vm: vm, onMultiplayerTap: onMultiplayerTap)
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
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(color)
        } else {
            VStack(spacing: 1) {
                Text("\(fraction.num)")
                    .font(.system(size: fontSize * 0.55, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
                Rectangle()
                    .fill(color.opacity(0.4))
                    .frame(height: 1.5)
                    .frame(maxWidth: fontSize * 1.8)
                Text("\(fraction.den)")
                    .font(.system(size: fontSize * 0.55, weight: .semibold, design: .rounded))
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Game View

struct GameView: View {
    @ObservedObject var vm: GameViewModel
    var onMultiplayerTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Text(vm.timerString)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.black.opacity(0.4))

                Spacer()

                if let onMultiplayerTap {
                    Button {
                        Haptics.light()
                        onMultiplayerTap()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 15, weight: .medium))
                            Text("Multiplayer")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.black.opacity(0.35))
                    }
                    Spacer()
                }

                Button {
                    Haptics.light()
                    vm.revealNextStep()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 18, weight: .medium))
                        if vm.showingSolution && !vm.solutionFullyRevealed {
                            Text("Next")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                    }
                    .foregroundColor(vm.solutionFullyRevealed ? .black.opacity(0.15) : .black.opacity(0.35))
                }
                .disabled(vm.solutionFullyRevealed)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            // Title
            Text(vm.message)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.bottom, 32)

            // Cards 2x2
            if !vm.showingSolution {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                    GridItem(.flexible(), spacing: 16)], spacing: 16) {
                    ForEach(Array(vm.cards.enumerated()), id: \.element.id) { index, card in
                        MinimalCardView(
                            fraction: card.value,
                            isSelected: vm.selectedCardIndex == index,
                            isVisible: card.isVisible
                        )
                        .onTapGesture {
                            Haptics.selection()
                            vm.handleCardTap(at: index)
                        }
                    }
                }
                .padding(.horizontal, 32)
            } else {
                // Show revealed steps
                SolutionStepsView(
                    solution: Array((vm.allSolutions.first ?? []).prefix(vm.revealedStepCount))
                )
                .padding(.horizontal, 32)
            }

            Spacer()

            // Operators
            if !vm.showingSolution {
                HStack(spacing: 0) {
                    ForEach(MathOperator.allCases, id: \.self) { op in
                        Button {
                            Haptics.light()
                            vm.selectedOperator = op
                        } label: {
                            Text(op.rawValue)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundColor(vm.selectedOperator == op ? .white : .black)
                                .background(
                                    vm.selectedOperator == op
                                        ? Color.black
                                        : Color.clear
                                )
                        }
                    }
                }
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14))
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
                BottomButton(label: "New Game", icon: "arrow.right", filled: true) {
                    Haptics.heavy()
                    vm.generateNewPuzzle()
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
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .padding(.bottom, 4)

            Text("\(vm.timerString)")
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(.black.opacity(0.4))
                .padding(.bottom, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(vm.allSolutions.count) solution\(vm.allSolutions.count == 1 ? "" : "s") found")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black.opacity(0.4))
                        .padding(.horizontal, 32)

                    ForEach(Array(vm.allSolutions.prefix(50).enumerated()), id: \.offset) { idx, solution in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Solution \(idx + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black.opacity(0.35))

                            ForEach(Array(solution.enumerated()), id: \.offset) { _, step in
                                Text("\(step.a) \(step.op) \(step.b) = \(step.result)")
                                    .font(.system(size: 17, weight: .regular, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.8))
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 32)
                    }
                }
            }

            Spacer()

            Button {
                Haptics.heavy()
                vm.generateNewPuzzle()
            } label: {
                Text("Next Game")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Subviews

struct MinimalCardView: View {
    let fraction: Fraction
    let isSelected: Bool
    let isVisible: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.black : Color.black.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(isSelected ? 1 : 0.08), lineWidth: 1.5)
                )

            FractionView(
                fraction: fraction,
                fontSize: 36,
                color: isSelected ? .white : .black
            )
        }
        .frame(height: 110)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .animation(.spring(response: 0.3), value: isVisible)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

struct SolutionStepsView: View {
    let solution: [SolutionStep]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(solution.enumerated()), id: \.offset) { _, step in
                HStack {
                    Text("\(step.a) \(step.op) \(step.b) = \(step.result)")
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundColor(.black.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: solution.count)
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
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(filled ? Color.black : Color.black.opacity(enabled ? 0.05 : 0.03))
            .foregroundColor(filled ? .white : .black.opacity(enabled ? 1 : 0.25))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!enabled)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
