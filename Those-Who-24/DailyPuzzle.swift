import SwiftUI

@Observable
@MainActor
final class DailyPuzzleManager {
    static let shared = DailyPuzzleManager()

    private(set) var puzzle: DailyPuzzleState?
    private(set) var schoolLeaderboard: [SchoolDailyLeaderboardEntry] = []
    private(set) var friendsLeaderboard: [DailyLeaderboardEntry] = []
    private(set) var solution: String?
    private(set) var university = UniversityStatus(schoolKey: UniversityCatalog.none.id)
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let service = SupabaseService.shared
    private let firstCompletionKey = "hasCompletedFirstDailyPuzzle"
    private let solutionDateKey = "dailyPuzzleSolutionDate"
    private let solutionMovesKey = "dailyPuzzleSolutionMoves"
    private let pendingSubmissionDateKey = "pendingDailyPuzzleSubmissionDate"
    private let pendingSubmissionMovesKey = "pendingDailyPuzzleSubmissionMoves"
    private let cachedUniversityKey = "cachedUniversitySchoolKey"

    private init() {
        if let schoolKey = UserDefaults.standard.string(forKey: cachedUniversityKey) {
            university = UniversityStatus(schoolKey: schoolKey)
        }
    }

    var utcDateKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    var hasCompletedToday: Bool {
        puzzle?.puzzleDate == utcDateKey && puzzle?.completedMilliseconds != nil
    }

    var isFirstDailyExperience: Bool {
        !UserDefaults.standard.bool(forKey: firstCompletionKey)
    }

    func startToday() async -> DailyPuzzleState? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let state = try await service.startDailyPuzzle()
            puzzle = state
            loadSolution(for: state.puzzleDate)
            return state
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func refreshTodayStatus() async -> Bool {
        do {
            puzzle = try await service.fetchDailyPuzzleStatus()
            if let puzzle {
                loadSolution(for: puzzle.puzzleDate)
            }
            if puzzle?.completedMilliseconds != nil {
                UserDefaults.standard.set(true, forKey: firstCompletionKey)
                clearPendingSubmission(for: puzzle?.puzzleDate)
            } else if let puzzle,
                      let pending = pendingSubmission(for: puzzle.puzzleDate) {
                _ = await submitToday(solution: pending)
            }
            if let puzzle, let milliseconds = puzzle.completedMilliseconds {
                StatsManager.shared.recordDailySolve(
                    puzzleDate: puzzle.puzzleDate,
                    milliseconds: milliseconds,
                    numbers: puzzle.numbers
                )
            }
            return true
        } catch {
            // Keep the prompt available when status cannot be refreshed. Tapping it
            // retries through startToday(), which surfaces a user-facing error.
            return false
        }
    }

    func submitToday(solution: String) async -> Bool {
        guard let puzzle, !isSubmitting else { return false }
        storePendingSubmission(solution, for: puzzle.puzzleDate)
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let milliseconds = try await service.submitDailyPuzzle(
                puzzleDate: puzzle.puzzleDate,
                solution: solution
            )
            self.puzzle = DailyPuzzleState(
                puzzleDate: puzzle.puzzleDate,
                numbers: puzzle.numbers,
                startedAt: puzzle.startedAt,
                completedMilliseconds: milliseconds
            )
            storeSolution(solution, for: puzzle.puzzleDate)
            clearPendingSubmission(for: puzzle.puzzleDate)
            StatsManager.shared.recordDailySolve(
                puzzleDate: puzzle.puzzleDate,
                milliseconds: milliseconds,
                numbers: puzzle.numbers
            )
            UserDefaults.standard.set(true, forKey: firstCompletionKey)
            PushNotificationManager.shared.cancelDailyPuzzleReminder()
            Task { await service.sendDailySolveNotification() }
            await refreshLeaderboard(for: puzzle.puzzleDate)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshLeaderboard(for puzzleDate: String? = nil) async {
        do {
            async let schools = service.fetchSchoolDailyLeaderboard(puzzleDate: puzzleDate)
            async let friends = service.fetchFriendsDailyLeaderboard(puzzleDate: puzzleDate)
            async let status = service.fetchUniversityStatus()
            schoolLeaderboard = try await schools
            friendsLeaderboard = try await friends
            updateUniversity(try await status)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshUniversity() async {
        do {
            updateUniversity(try await service.fetchUniversityStatus())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectUniversity(_ option: UniversityOption) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            updateUniversity(try await service.selectUniversity(option.id))
            await refreshLeaderboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateUniversity(_ status: UniversityStatus) {
        university = status
        UserDefaults.standard.set(status.schoolKey, forKey: cachedUniversityKey)
    }

    private func loadSolution(for puzzleDate: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: solutionDateKey) == puzzleDate else {
            defaults.removeObject(forKey: solutionDateKey)
            defaults.removeObject(forKey: solutionMovesKey)
            solution = nil
            return
        }
        solution = defaults.string(forKey: solutionMovesKey)
    }

    private func storeSolution(_ moves: String, for puzzleDate: String) {
        UserDefaults.standard.set(puzzleDate, forKey: solutionDateKey)
        UserDefaults.standard.set(moves, forKey: solutionMovesKey)
        solution = moves
    }

    func pendingSubmission(for puzzleDate: String) -> String? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: pendingSubmissionDateKey) == puzzleDate else { return nil }
        return defaults.string(forKey: pendingSubmissionMovesKey)
    }

    private func storePendingSubmission(_ moves: String, for puzzleDate: String) {
        let defaults = UserDefaults.standard
        defaults.set(puzzleDate, forKey: pendingSubmissionDateKey)
        defaults.set(moves, forKey: pendingSubmissionMovesKey)
    }

    private func clearPendingSubmission(for puzzleDate: String?) {
        let defaults = UserDefaults.standard
        guard puzzleDate == nil || defaults.string(forKey: pendingSubmissionDateKey) == puzzleDate else { return }
        defaults.removeObject(forKey: pendingSubmissionDateKey)
        defaults.removeObject(forKey: pendingSubmissionMovesKey)
    }
}

struct DailyPuzzleView: View {
    let puzzle: DailyPuzzleState
    let onDismiss: () -> Void

    @StateObject private var vm = GameViewModel()
    @State private var manager = DailyPuzzleManager.shared
    @State private var isConfigured = false
    @State private var showResults = false
    @State private var showConfetti = false
    @State private var isAwaitingSaveRetry = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if showResults {
                DailyResultsView(
                    manager: manager,
                    puzzle: manager.puzzle ?? puzzle,
                    onDone: onDismiss
                )
                .transition(.opacity)
            } else if isAwaitingSaveRetry {
                VStack(spacing: 18) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 38))
                        .foregroundColor(Theme.amber)
                    Text("Your solve is safe on this device")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.brown)
                        .multilineTextAlignment(.center)
                    Text("Reconnect and retry. You do not need to solve the puzzle again.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry Save") { retryPendingSubmission() }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundColor(Theme.cardSelectedText)
                        .background(Theme.buttonPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Button("Exit for Now", action: onDismiss)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(28)
                .background(Theme.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 28)
            } else if isConfigured {
                GameView(
                    vm: vm,
                    isDailyPuzzle: true,
                    onDailyExit: onDismiss
                )
            } else {
                ProgressView()
                    .tint(Theme.amber)
            }

            if manager.isSubmitting {
                Theme.backgroundTop.opacity(0.75).ignoresSafeArea()
                ProgressView("Saving your time…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .tint(Theme.amber)
                    .foregroundColor(Theme.brown)
            }

            if showConfetti {
                DailyConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
        .task {
            guard !isConfigured else { return }
            if puzzle.completedMilliseconds != nil {
                await manager.refreshLeaderboard(for: puzzle.puzzleDate)
                showResults = true
                isConfigured = true
                return
            }

            if manager.pendingSubmission(for: puzzle.puzzleDate) != nil {
                isConfigured = true
                isAwaitingSaveRetry = true
                retryPendingSubmission()
                return
            }

            vm.setupDailyPuzzle(
                numbers: puzzle.numbers,
                startedAt: puzzle.startedAt ?? Date()
            ) { _ in
                let solution = vm.playerMoves.map {
                    "\($0.firstIdx):\($0.secondIdx):\($0.op):\($0.resultLabel)"
                }.joined(separator: ",")
                Task { await saveAndShowResults(solution: solution) }
            }
            isConfigured = true
        }
        .onChange(of: manager.hasCompletedToday) { _, completed in
            guard completed, manager.puzzle?.puzzleDate == puzzle.puzzleDate else { return }
            isAwaitingSaveRetry = false
            withAnimation(.easeInOut(duration: 0.25)) {
                showResults = true
            }
        }
        .alert("Couldn’t save your solve", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            if manager.pendingSubmission(for: puzzle.puzzleDate) != nil {
                Button("Try Again") { retryPendingSubmission() }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private func retryPendingSubmission() {
        guard let pending = manager.pendingSubmission(for: puzzle.puzzleDate) else { return }
        Task { await saveAndShowResults(solution: pending) }
    }

    private func saveAndShowResults(solution: String) async {
        guard await manager.submitToday(solution: solution) else {
            isAwaitingSaveRetry = true
            return
        }
        isAwaitingSaveRetry = false
        withAnimation(.easeInOut(duration: 0.25)) {
            showResults = true
        }
        showConfetti = true
        try? await Task.sleep(for: .seconds(1.75))
        showConfetti = false
    }
}

private struct DailyConfettiView: View {
    @State private var didPop = false
    private let pieceCount = 72

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<pieceCount, id: \.self) { index in
                    confettiPiece(index)
                        .rotationEffect(.degrees(didPop ? Double(index * 91 + 480) : Double(index * 17)))
                        .position(
                            x: popX(index, size: geometry.size),
                            y: popY(index, size: geometry.size)
                        )
                        .opacity(didPop ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.15 + Double(index % 6) * 0.08)
                                .delay(Double(index % 10) * 0.015),
                            value: didPop
                        )
                }
            }
        }
        .onAppear {
            didPop = true
        }
        .accessibilityHidden(true)
    }

    private func popX(_ index: Int, size: CGSize) -> CGFloat {
        guard didPop else { return size.width / 2 }
        let angle = Double(index) / Double(pieceCount) * Double.pi * 2
        let distance = CGFloat(145 + (index * 47) % 210)
        return size.width / 2 + CGFloat(cos(angle)) * distance
    }

    private func popY(_ index: Int, size: CGSize) -> CGFloat {
        let origin = min(size.height * 0.23, 220)
        guard didPop else { return origin }
        let angle = Double(index) / Double(pieceCount) * Double.pi * 2
        let distance = CGFloat(125 + (index * 39) % 190)
        return origin + CGFloat(sin(angle)) * distance + 70
    }

    @ViewBuilder
    private func confettiPiece(_ index: Int) -> some View {
        if index.isMultiple(of: 11) {
            Circle()
                .stroke(confettiColor(index), lineWidth: 2.5)
                .frame(
                    width: CGFloat(30 + (index % 3) * 10),
                    height: CGFloat(30 + (index % 3) * 10)
                )
        } else if index.isMultiple(of: 5) {
            Circle()
                .fill(confettiColor(index))
                .frame(width: 14, height: 14)
        } else {
            RoundedRectangle(cornerRadius: index.isMultiple(of: 3) ? 4 : 1.5)
                .fill(confettiColor(index))
                .frame(
                    width: index.isMultiple(of: 4) ? 12 : 18,
                    height: index.isMultiple(of: 3) ? 20 : 9
                )
        }
    }

    private func confettiColor(_ index: Int) -> Color {
        let celebrationColors: [Color] = [
            .pink,
            .cyan,
            .blue,
            .green,
            .yellow,
            .orange,
            .purple,
            .red
        ]
        return celebrationColors[index % celebrationColors.count]
    }
}

struct DailyResultsView: View {
    private enum LeaderboardKind: String, CaseIterable {
        case schools = "Schools"
        case friends = "Friends"
    }

    @Bindable var manager: DailyPuzzleManager
    let puzzle: DailyPuzzleState
    let onDone: () -> Void
    @State private var selectedKind: LeaderboardKind = .schools

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 34))
                                .foregroundColor(Theme.amber)
                            Text("Daily puzzle solved!")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.brown)
                            HStack(spacing: 5) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 13))
                                Text(format(milliseconds: puzzle.completedMilliseconds ?? 0))
                                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                            }
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.vertical, 12)

                        HStack(spacing: 12) {
                            statCard(
                                label: "Friend rank",
                                value: currentFriendRank.map { "#\($0)" } ?? "—"
                            )
                            statCard(
                                label: "School rank",
                                value: currentSchoolRank.map { "#\($0)" } ?? "—"
                            )
                        }

                        if !replayMoves.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Your solution")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.brown)

                                CardAnimationView(numbers: puzzle.numbers, moves: replayMoves)
                            }
                            .padding(16)
                            .background(Theme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(Theme.amber)
                            Text("Leaderboards")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.brown)
                            Spacer()
                        }
                        .padding(.top, 14)

                        Picker("Leaderboard", selection: $selectedKind) {
                            ForEach(LeaderboardKind.allCases, id: \.self) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        if selectedKind == .schools {
                            schoolResults
                        } else {
                            friendResults
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("ThoseWho24")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: onDone) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.brown)
                            .frame(width: 32, height: 32)
                            .background(Theme.cream)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close daily results")
                }
            }
        }
        .task {
            await manager.refreshLeaderboard(for: puzzle.puzzleDate)
        }
    }

    private var replayMoves: [WinnerMove] {
        guard let solution = manager.solution, !solution.isEmpty else { return [] }
        return solution.components(separatedBy: ",").compactMap { token in
            let parts = token.components(separatedBy: ":")
            guard parts.count >= 4,
                  let first = Int(parts[0]),
                  let second = Int(parts[1]) else { return nil }
            return WinnerMove(
                firstIdx: first,
                secondIdx: second,
                op: parts[2],
                result: parts[3]
            )
        }
    }

    private var currentFriendRank: Int? {
        manager.friendsLeaderboard.first(where: \.isCurrentUser)?.rank
    }

    private var currentSchoolRank: Int? {
        manager.schoolLeaderboard.first(where: \.isCurrentSchool)?.rank
    }

    private func statCard(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var schoolResults: some View {
        if manager.schoolLeaderboard.isEmpty {
            emptyState(
                title: "No school results yet",
                detail: "School averages appear after players finish today’s puzzle."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(manager.schoolLeaderboard) { entry in
                    NavigationLink {
                        SchoolDailyLeaderboardView(
                            schoolKey: entry.schoolKey,
                            puzzleDate: puzzle.puzzleDate
                        )
                    } label: {
                        HStack(spacing: 12) {
                            rankLabel(entry.rank)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(UniversityCatalog.displayName(for: entry.schoolKey))
                                    .font(.system(size: 16, weight: entry.isCurrentSchool ? .bold : .semibold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                Text("\(entry.solverCount) solver\(entry.solverCount == 1 ? "" : "s")")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Text(format(milliseconds: entry.averageMilliseconds))
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.textSecondary.opacity(0.7))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(entry.isCurrentSchool ? Theme.amber.opacity(0.14) : Color.clear)
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.25)
                }
            }
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private var friendResults: some View {
        if manager.friendsLeaderboard.isEmpty {
            emptyState(
                title: "No friend results yet",
                detail: "Your time and completed solves from accepted friends appear here."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(manager.friendsLeaderboard) { entry in
                    HStack(spacing: 12) {
                        rankLabel(entry.rank)
                        if entry.isCurrentUser {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("You")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                HStack(spacing: 6) {
                                    Text("@\(entry.username)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(Theme.textSecondary)
                                        .fixedSize(horizontal: true, vertical: false)
                                    FounderTag(username: entry.username)
                                }
                            }
                        } else {
                            HStack(spacing: 6) {
                                Text("@\(entry.username)")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                    .fixedSize(horizontal: true, vertical: false)
                                FounderTag(username: entry.username)
                            }
                        }
                        Spacer()
                        Text(format(milliseconds: entry.completedMilliseconds))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(entry.isCurrentUser ? Theme.amber.opacity(0.14) : Color.clear)
                    Divider().opacity(0.25)
                }
            }
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
            Text(detail)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func rankLabel(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(rank <= 3 ? Theme.amber : Theme.textSecondary)
            .frame(width: 30)
    }

    private func format(milliseconds: Int) -> String {
        let totalSeconds = Double(milliseconds) / 1000
        if totalSeconds < 60 { return String(format: "%.2fs", totalSeconds) }
        return String(format: "%d:%05.2f", Int(totalSeconds) / 60, totalSeconds.truncatingRemainder(dividingBy: 60))
    }
}

private struct SchoolDailyLeaderboardView: View {
    let schoolKey: String
    let puzzleDate: String

    @State private var entries: [DailyLeaderboardEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading leaderboard…")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(UniversityCatalog.displayName(for: schoolKey))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.brown)
                            Text("Today’s individual solve times")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(Theme.textSecondary)
                        }

                        if entries.isEmpty {
                            emptyState
                        } else {
                            leaderboard
                        }
                    }
                    .padding(24)
                }
                .refreshable { await loadLeaderboard() }
            }
        }
        .navigationTitle("School leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: schoolKey) { await loadLeaderboard() }
        .alert("Couldn’t load leaderboard", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Try Again") { Task { await loadLeaderboard() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var leaderboard: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Text("\(entry.rank)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(entry.rank <= 3 ? Theme.amber : Theme.textSecondary)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        if entry.isCurrentUser {
                            Text("You")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundColor(Theme.brown)
                        }
                        HStack(spacing: 6) {
                            Text("@\(entry.username)")
                                .font(.system(size: entry.isCurrentUser ? 12 : 16, weight: .semibold, design: .rounded))
                                .foregroundColor(entry.isCurrentUser ? Theme.textSecondary : Theme.brown)
                                .fixedSize(horizontal: true, vertical: false)
                            FounderTag(username: entry.username)
                        }
                    }

                    Spacer()

                    Text(format(milliseconds: entry.completedMilliseconds))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(entry.isCurrentUser ? Theme.amber.opacity(0.14) : Color.clear)

                if entry.id != entries.last?.id {
                    Divider().opacity(0.25)
                }
            }
        }
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No individual results yet")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
            Text("Completed solves from this university will appear here.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func loadLeaderboard() async {
        isLoading = entries.isEmpty
        defer { isLoading = false }

        do {
            entries = try await SupabaseService.shared.fetchSchoolMembersDailyLeaderboard(
                schoolKey: schoolKey,
                puzzleDate: puzzleDate
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func format(milliseconds: Int) -> String {
        let totalSeconds = Double(milliseconds) / 1_000
        if totalSeconds < 60 { return String(format: "%.2fs", totalSeconds) }
        return String(
            format: "%d:%05.2f",
            Int(totalSeconds) / 60,
            totalSeconds.truncatingRemainder(dividingBy: 60)
        )
    }
}

struct UniversitySettingsView: View {
    @Bindable var manager: DailyPuzzleManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var options: [UniversityOption] {
        let all = [UniversityCatalog.none] + UniversityCatalog.universities
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.matches(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a university so your solve contributes to its daily average. No email or verification is required.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(Theme.textSecondary)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(options) { option in
                                Button {
                                    Task {
                                        if await manager.selectUniversity(option) { dismiss() }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: option.id == UniversityCatalog.none.id ? "person.fill" : "graduationcap.fill")
                                            .foregroundColor(Theme.amber)
                                            .frame(width: 24)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(option.name)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(Theme.brown)
                                                .multilineTextAlignment(.leading)
                                            if !option.location.isEmpty {
                                                Text(option.location)
                                                    .font(.system(size: 12, design: .rounded))
                                                    .foregroundColor(Theme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        if manager.university.schoolKey == option.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(Theme.amber)
                                        }
                                    }
                                    .padding(14)
                                    .background(Theme.cream)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .disabled(manager.isLoading)
                            }
                        }
                    }

                    if let error = manager.errorMessage {
                        Text(error)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.destructiveText)
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("University")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search name, state, or country")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.brown)
                }
            }
        }
        .task {
            await manager.refreshUniversity()
        }
    }
}
