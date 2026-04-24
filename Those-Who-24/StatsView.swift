import SwiftUI
import Combine

// MARK: - Solve Record

struct SolveRecord: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let seconds: Int
    let numbers: [Int]
}

// MARK: - Stats Manager

class StatsManager: ObservableObject {
    static let shared = StatsManager()

    @Published private(set) var solves: [SolveRecord] = []

    private let key = "solveRecords"

    private init() {
        load()
    }

    func recordSolve(seconds: Int, numbers: [Int]) {
        let record = SolveRecord(date: Date(), seconds: seconds, numbers: numbers)
        solves.append(record)
        save()
    }

    var lifetimeSolves: Int { solves.count }

    var uniqueProblemsSolved: Int {
        let unique = Set(solves.map { $0.numbers.sorted().map(String.init).joined(separator: ",") })
        return unique.count
    }

    var averageSeconds: Int {
        guard !solves.isEmpty else { return 0 }
        let total = solves.reduce(0) { $0 + $1.seconds }
        return total / solves.count
    }

    private func save() {
        if let data = try? JSONEncoder().encode(solves) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SolveRecord].self, from: data) else { return }
        solves = decoded
    }
}

// MARK: - Stats View

struct StatsView: View {
    let onBack: () -> Void
    @ObservedObject private var stats = StatsManager.shared

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button {
                    Haptics.light()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Back")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Text("Stats")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                ScrollView {
                    VStack(spacing: 16) {
                        StatCard(
                            value: "\(stats.lifetimeSolves)",
                            label: "Lifetime solves"
                        )
                        StatCard(
                            value: "\(stats.uniqueProblemsSolved)",
                            label: "Unique problems solved"
                        )
                        StatCard(
                            value: formatTime(stats.averageSeconds),
                            label: "Average time per solve"
                        )

                        if stats.solves.count >= 2 {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Solve time over time")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal, 24)

                                SolveTimeChart(solves: stats.solves)
                                    .frame(height: 200)
                                    .padding(.horizontal, 24)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.brown)
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }
}

// MARK: - Solve Time Chart

private struct SolveTimeChart: View {
    let solves: [SolveRecord]

    private var recentSolves: [SolveRecord] {
        Array(solves.suffix(20))
    }

    private var maxSeconds: Int {
        max((recentSolves.map(\.seconds).max() ?? 60), 10)
    }

    private var yTicks: [Int] {
        let top = maxSeconds
        if top <= 30 { return stride(from: 0, through: top, by: 10).map { $0 } }
        if top <= 120 { return stride(from: 0, through: top, by: 30).map { $0 } }
        return stride(from: 0, through: top, by: 60).map { $0 }
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    var body: some View {
        GeometryReader { geo in
            let padding = EdgeInsets(top: 16, leading: 44, bottom: 28, trailing: 16)
            let chartWidth = geo.size.width - padding.leading - padding.trailing
            let chartHeight = geo.size.height - padding.top - padding.bottom
            let points = recentSolves.enumerated().map { i, solve -> CGPoint in
                let x = padding.leading + (recentSolves.count == 1 ? chartWidth / 2 : chartWidth * CGFloat(i) / CGFloat(recentSolves.count - 1))
                let y = padding.top + chartHeight * (1 - CGFloat(solve.seconds) / CGFloat(maxSeconds))
                return CGPoint(x: x, y: y)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cream)

                // Y-axis labels + grid lines
                ForEach(yTicks, id: \.self) { tick in
                    let y = padding.top + chartHeight * (1 - CGFloat(tick) / CGFloat(maxSeconds))
                    Text(formatTickLabel(tick))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .position(x: padding.leading / 2, y: y)

                    Path { path in
                        path.move(to: CGPoint(x: padding.leading, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width - padding.trailing, y: y))
                    }
                    .stroke(Theme.brown.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                // Line
                if points.count >= 2 {
                    Path { path in
                        path.move(to: points[0])
                        for p in points.dropFirst() {
                            path.addLine(to: p)
                        }
                    }
                    .stroke(Theme.brown, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                // Dots
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Theme.brown)
                        .frame(width: 7, height: 7)
                        .position(point)
                }

                // X-axis labels
                if let first = recentSolves.first, let last = recentSolves.last, recentSolves.count >= 2 {
                    let xLabelY = geo.size.height - 6
                    Text(dateFormatter.string(from: first.date))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .position(x: points.first?.x ?? padding.leading, y: xLabelY)

                    Text(dateFormatter.string(from: last.date))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .position(x: points.last?.x ?? (geo.size.width - padding.trailing), y: xLabelY)

                    if recentSolves.count >= 5 {
                        let midIndex = recentSolves.count / 2
                        Text(dateFormatter.string(from: recentSolves[midIndex].date))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.textMuted)
                            .position(x: points[midIndex].x, y: xLabelY)
                    }
                }
            }
        }
    }

    private func formatTickLabel(_ seconds: Int) -> String {
        if seconds == 0 { return "0" }
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m):00" : String(format: "%d:%02d", m, s)
    }
}
