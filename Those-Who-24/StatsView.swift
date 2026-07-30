import SwiftUI
import Combine

// MARK: - Solve Record

struct SolveRecord: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let seconds: Double
    let numbers: [Int]
}

// MARK: - Stats Manager

class StatsManager: ObservableObject {
    static let shared = StatsManager()

    @Published private(set) var solves: [SolveRecord] = []

    private let key = "solveRecords"

    private init() { load() }

    func recordSolve(seconds: Double, numbers: [Int]) {
        let record = SolveRecord(date: Date(), seconds: seconds, numbers: numbers)
        solves.append(record)
        save()
    }

    func reset() {
        solves = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    var lifetimeSolves: Int { solves.count }

    var uniqueProblemsSolved: Int {
        Set(solves.map { $0.numbers.sorted().map(String.init).joined(separator: ",") }).count
    }

    var personalBest: Double? { solves.map(\.seconds).min() }

    var p10: Double? {
        guard !solves.isEmpty else { return nil }
        let sorted = solves.map(\.seconds).sorted()
        let i = 0.10 * Double(sorted.count - 1)
        let lo = Int(i), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (i - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    var totalTimeSeconds: Int { Int(solves.reduce(0.0) { $0 + $1.seconds }) }

    var medianSeconds: Double? {
        guard !solves.isEmpty else { return nil }
        let sorted = solves.map(\.seconds).sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0
            ? (sorted[mid - 1] + sorted[mid]) / 2.0
            : sorted[mid]
    }

    // A solve this far above the median is an interruption, not an attempt.
    // Median-relative so the rule holds for both fast and slow players.
    private let outlierMedianMultiple = 5.0

    func withoutOutliers(_ records: [SolveRecord]) -> [SolveRecord] {
        guard let median = medianSeconds else { return records }
        let threshold = median * outlierMedianMultiple
        return records.filter { $0.seconds <= threshold }
    }

    // AoN over most recent N solves
    func averageOf(_ n: Int) -> Double? {
        guard solves.count >= n else { return nil }
        let drop = n <= 12 ? 1 : 5
        let sorted = solves.suffix(n).map(\.seconds).sorted()
        let trimmed = sorted.dropFirst(drop).dropLast(drop)
        return trimmed.reduce(0.0, +) / Double(trimmed.count)
    }

    // Best aoN ever — scan every rolling window of N in solve history
    func bestAverageOf(_ n: Int) -> Double? {
        guard solves.count >= n else { return nil }
        let drop = n <= 12 ? 1 : 5
        let times = solves.map(\.seconds)
        var best: Double? = nil
        for i in (n - 1)..<times.count {
            let slice = Array(times[(i - n + 1)...i]).sorted()
            let trimmed = slice.dropFirst(drop).dropLast(drop)
            let avg = trimmed.reduce(0.0, +) / Double(trimmed.count)
            if best == nil || avg < best! { best = avg }
        }
        return best
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

// MARK: - Time Frame

enum TimeFrame: String, CaseIterable {
    case last50 = "50", last100 = "100", last500 = "500", allTime = "All"

    func apply(_ solves: [SolveRecord]) -> [SolveRecord] {
        switch self {
        case .last50:  return Array(solves.suffix(50))
        case .last100: return Array(solves.suffix(100))
        case .last500: return Array(solves.suffix(500))
        case .allTime: return solves
        }
    }
}

// MARK: - Stats View

struct StatsView: View {
    let onBack: () -> Void
    @ObservedObject private var stats = StatsManager.shared
    @State private var timeFrame: TimeFrame = .last100

    private var filteredSolves: [SolveRecord] { timeFrame.apply(stats.solves) }

    // Trend runs on outlier-free solves; `warmup` is the pre-window context
    // that primes the rolling metrics and is not itself displayed.
    private var trendData: (warmup: [SolveRecord], window: [SolveRecord]) {
        let all = stats.withoutOutliers(stats.solves)
        let window = timeFrame.apply(all)
        let startIdx = all.count - window.count
        guard startIdx > 0 else { return ([], window) }
        return (Array(all[max(0, startIdx - 11)..<startIdx]), window)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Navigation header
                HStack {
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

                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Text("Stats")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 20) {
                        allTimeSection
                        if stats.solves.count >= 5 {
                            recentSection
                        }
                        if stats.solves.count >= 2 {
                            graphSection
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var allTimeSection: some View {
        VStack(spacing: 20) {
            // Speed
            VStack(spacing: 10) {
                SectionHeader(title: "Speed", subtitle: "All time, single solve")
                HStack(spacing: 10) {
                    StatCard(value: stats.personalBest.map { formatSecs($0) } ?? "—", label: "Best")
                    StatCard(value: stats.medianSeconds.map { formatSecs($0) } ?? "—",        label: "Median")
                    StatCard(value: stats.p10.map { formatSecs($0) } ?? "—",                  label: "P10")
                }
                .padding(.horizontal, 24)
            }

            // Volume
            VStack(spacing: 10) {
                SectionHeader(title: "Volume", subtitle: "All time")
                HStack(spacing: 10) {
                    StatCard(value: formatCount(stats.lifetimeSolves),      label: "Solves")
                    StatCard(value: formatCount(stats.uniqueProblemsSolved), label: "Unique puzzles")
                    StatCard(value: formatTotalTime(stats.totalTimeSeconds), label: "Time spent")
                }
                .padding(.horizontal, 24)
            }

            // Personal records
            VStack(spacing: 10) {
                SectionHeader(title: "Personal Records", subtitle: "Best rolling average, ever")
                HStack(spacing: 10) {
                    StatCard(value: stats.bestAverageOf(5).map   { formatSecs($0) } ?? "—", label: "Best ao5")
                    StatCard(value: stats.bestAverageOf(12).map  { formatSecs($0) } ?? "—", label: "Best ao12")
                    StatCard(value: stats.bestAverageOf(100).map { formatSecs($0) } ?? "—", label: "Best ao100")
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Recent", subtitle: "Last 5/12/100 solves, outliers trimmed")
            HStack(spacing: 10) {
                StatCard(value: stats.averageOf(5).map   { formatSecs($0) } ?? "—", label: "ao5")
                StatCard(value: stats.averageOf(12).map  { formatSecs($0) } ?? "—", label: "ao12")
                StatCard(value: stats.averageOf(100).map { formatSecs($0) } ?? "—", label: "ao100")
            }
            .padding(.horizontal, 24)
        }
    }

    private var graphSection: some View {
        VStack(spacing: 10) {
            trendSection
            distributionSection
        }
    }

    private var timeFramePicker: some View {
        HStack(spacing: 0) {
            ForEach(TimeFrame.allCases, id: \.self) { tf in
                Button {
                    Haptics.light()
                    timeFrame = tf
                } label: {
                    Text(tf.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(timeFrame == tf ? Theme.brown : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(timeFrame == tf ? Theme.cream : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }

    private var trendSection: some View {
        let trend = trendData

        return VStack(spacing: 10) {
            SectionHeader(title: "Trend", subtitle: "Rolling ao12 + IQR spread, outliers excluded")

            timeFramePicker

            RollingTrendChart(warmupSolves: trend.warmup, solves: trend.window)
                .frame(height: 200)
                .padding(.horizontal, 24)
        }
    }

    private var distributionSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "Distribution", subtitle: "Solve count by time bucket")

            DistributionChart(solves: filteredSolves)
                .frame(height: 140)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Formatters

    private func formatSecs(_ s: Double) -> String {
        if s < 60 { return String(format: "%.2fs", s) }
        let m = Int(s) / 60
        let rem = s.truncatingRemainder(dividingBy: 60)
        return rem < 0.005 ? "\(m)m" : String(format: "%d:%05.2f", m, rem)
    }

    private func formatCount(_ n: Int) -> String { n.formatted() }

    private func formatTotalTime(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textMuted)
                .tracking(0.8)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.brown)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Rolling Trend Chart

private struct RollingTrendChart: View {
    let warmupSolves: [SolveRecord]   // pre-window context, not displayed
    let solves: [SolveRecord]         // visible window

    private struct Ao12Point { let idx: Int; let val: Double }

    private struct PlotData {
        let q1: [Double]
        let q3: [Double]
        let ao12: [Ao12Point]
        let yMax: Double
        let yTicks: [Double]
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let i = p * Double(sorted.count - 1)
        let lo = Int(i), hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (i - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    private func computeTicks(_ max: Double) -> [Double] {
        let step: Double
        if max <= 10       { step = 2  }
        else if max <= 30  { step = 5  }
        else if max <= 60  { step = 15 }
        else if max <= 120 { step = 30 }
        else               { step = 60 }
        var out: [Double] = []
        var t = 0.0
        while t <= max { out.append(t); t += step }
        return out
    }

    private func tickLabel(_ s: Double) -> String {
        if s == 0 { return "0" }
        if s < 60 { return "\(Int(s))s" }
        return "\(Int(s / 60))m"
    }

    private var plotData: PlotData {
        let allTimes = (warmupSolves + solves).map(\.seconds)
        let offset = warmupSolves.count
        var allQ1: [Double] = [], allQ3: [Double] = []
        var allAo12: [Ao12Point] = []

        for i in allTimes.indices {
            // 12-solve rolling window matches the ao12 window
            let window = Array(allTimes[max(0, i - 11)...i]).sorted()
            allQ1.append(percentile(window, 0.25))
            allQ3.append(percentile(window, 0.75))

            if i >= 11 {
                let slice = Array(allTimes[(i - 11)...i]).sorted()
                let trimmed = slice.dropFirst(1).dropLast(1)
                allAo12.append(Ao12Point(idx: i, val: trimmed.reduce(0.0, +) / Double(trimmed.count)))
            }
        }

        // Trim to visible window only
        let q1 = Array(allQ1.dropFirst(offset))
        let q3 = Array(allQ3.dropFirst(offset))
        let ao12 = allAo12
            .filter { $0.idx >= offset }
            .map { Ao12Point(idx: $0.idx - offset, val: $0.val) }

        let yRaw = max(q3.max() ?? 30, ao12.map(\.val).max() ?? 30)
        let yMax = max(yRaw * 1.15, 5)
        return PlotData(q1: q1, q3: q3, ao12: ao12, yMax: yMax, yTicks: computeTicks(yMax))
    }

    var body: some View {
        let plot = plotData
        let n = solves.count
        let pL: CGFloat = 38, pR: CGFloat = 12, pT: CGFloat = 14, pB: CGFloat = 12

        GeometryReader { geo in
            let cw = geo.size.width - pL - pR
            let ch = geo.size.height - pT - pB

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16).fill(Theme.cream)

                Canvas { ctx, size in
                    let xOf: (Int) -> CGFloat = { i in
                        pL + (n <= 1 ? cw / 2 : cw * CGFloat(i) / CGFloat(n - 1))
                    }
                    let yOf: (Double) -> CGFloat = { v in
                        pT + ch * CGFloat(1.0 - v / plot.yMax)
                    }

                    // Grid lines
                    for tick in plot.yTicks {
                        var p = Path()
                        p.move(to: CGPoint(x: pL, y: yOf(tick)))
                        p.addLine(to: CGPoint(x: size.width - pR, y: yOf(tick)))
                        ctx.stroke(p, with: .color(Theme.brown.opacity(0.08)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }

                    guard n >= 2 else { return }

                    // IQR band (25th–75th percentile, same 12-solve window as ao12)
                    var band = Path()
                    band.move(to: CGPoint(x: xOf(0), y: yOf(plot.q3[0])))
                    for i in 1..<n { band.addLine(to: CGPoint(x: xOf(i), y: yOf(plot.q3[i]))) }
                    for i in stride(from: n - 1, through: 0, by: -1) {
                        band.addLine(to: CGPoint(x: xOf(i), y: yOf(plot.q1[i])))
                    }
                    band.closeSubpath()
                    ctx.fill(band, with: .color(Theme.brown.opacity(0.13)))

                    // ao12 line
                    guard plot.ao12.count >= 2 else { return }
                    var line = Path()
                    line.move(to: CGPoint(x: xOf(plot.ao12[0].idx), y: yOf(plot.ao12[0].val)))
                    for pt in plot.ao12.dropFirst() {
                        line.addLine(to: CGPoint(x: xOf(pt.idx), y: yOf(pt.val)))
                    }
                    ctx.stroke(line, with: .color(Theme.brown),
                               style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }

                // Y-axis labels
                ForEach(Array(plot.yTicks.enumerated()), id: \.offset) { _, tick in
                    let yy = pT + ch * CGFloat(1.0 - tick / plot.yMax)
                    Text(tickLabel(tick))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textMuted)
                        .position(x: pL / 2, y: yy)
                }
            }
        }
    }
}

// MARK: - Distribution Chart

private struct DistributionChart: View {
    let solves: [SolveRecord]

    private let buckets: [(label: String, lo: Int, hi: Int)] = [
        ("0–5s",   0,  5),
        ("5–10s",  5,  10),
        ("10–20s", 10, 20),
        ("20–60s", 20, 60),
        ("60s+",   60, Int.max),
    ]

    private var counts: [Int] {
        buckets.map { b in solves.filter { $0.seconds >= Double(b.lo) && $0.seconds < Double(b.hi) }.count }
    }

    var body: some View {
        let cnts = counts
        let maxCount = max(cnts.max() ?? 1, 1)

        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Theme.cream)

            GeometryReader { geo in
                let barAreaH = geo.size.height - 42
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(zip(buckets, cnts).enumerated()), id: \.offset) { _, pair in
                        let (bucket, count) = pair
                        let barH: CGFloat = count == 0
                            ? 2
                            : max(6, barAreaH * CGFloat(count) / CGFloat(maxCount))

                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            if count > 0 {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.bottom, 3)
                            }
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.brown.opacity(count == 0 ? 0.12 : 0.72))
                                .frame(height: barH)
                            Text(bucket.label)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.textMuted)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .padding(.top, 10)
            }
        }
    }
}
