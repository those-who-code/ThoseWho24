import SwiftUI

@Observable
@MainActor
final class DailyPuzzleManager {
    static let shared = DailyPuzzleManager()

    private(set) var puzzle: DailyPuzzleState?
    private(set) var schoolLeaderboard: [SchoolDailyLeaderboardEntry] = []
    private(set) var friendsLeaderboard: [DailyLeaderboardEntry] = []
    private(set) var solution: String?
    private(set) var university = UniversityStatus(email: nil, schoolKey: "non-school", isVerified: false)
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    var errorMessage: String?

    private let service = SupabaseService.shared
    private let firstCompletionKey = "hasCompletedFirstDailyPuzzle"
    private let solutionDateKey = "dailyPuzzleSolutionDate"
    private let solutionMovesKey = "dailyPuzzleSolutionMoves"

    private init() {}

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

    func refreshTodayStatus() async {
        do {
            puzzle = try await service.fetchDailyPuzzleStatus()
            if let puzzle {
                loadSolution(for: puzzle.puzzleDate)
            }
            if puzzle?.completedMilliseconds != nil {
                UserDefaults.standard.set(true, forKey: firstCompletionKey)
            }
        } catch {
            // Keep the prompt available when status cannot be refreshed. Tapping it
            // retries through startToday(), which surfaces a user-facing error.
        }
    }

    func submitToday(solution: String) async -> Bool {
        guard let puzzle else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let milliseconds = try await service.submitDailyPuzzle(puzzleDate: puzzle.puzzleDate)
            self.puzzle = DailyPuzzleState(
                puzzleDate: puzzle.puzzleDate,
                numbers: puzzle.numbers,
                startedAt: puzzle.startedAt,
                completedMilliseconds: milliseconds
            )
            storeSolution(solution, for: puzzle.puzzleDate)
            UserDefaults.standard.set(true, forKey: firstCompletionKey)
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
            university = try await status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshUniversity() async {
        do {
            university = try await service.fetchUniversityStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendVerification(email rawEmail: String) async -> Bool {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.isAcademicEmail(email) else {
            errorMessage = "Enter a university email such as name@school.edu."
            return false
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await service.sendUniversityVerification(to: email)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verify(email: String, code: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            university = try await service.verifyUniversityEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            await refreshLeaderboard()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func syncVerifiedEmail() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            university = try await service.syncVerifiedUniversityEmail()
            await refreshLeaderboard()
            return true
        } catch {
            errorMessage = "Open the verification email first, then try again."
            return false
        }
    }

    private static func isAcademicEmail(_ email: String) -> Bool {
        guard let domain = email.split(separator: "@").last.map(String.init) else { return false }
        return domain.hasSuffix(".edu") ||
            domain.range(of: #"\.ac\.[a-z]{2}$"#, options: .regularExpression) != nil ||
            domain.range(of: #"\.edu\.[a-z]{2}$"#, options: .regularExpression) != nil
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
}

struct DailyPuzzleView: View {
    let puzzle: DailyPuzzleState
    let onDismiss: () -> Void

    @StateObject private var vm = GameViewModel()
    @State private var manager = DailyPuzzleManager.shared
    @State private var isConfigured = false
    @State private var showResults = false
    @State private var showConfetti = false

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

            vm.setupDailyPuzzle(
                numbers: puzzle.numbers,
                startedAt: puzzle.startedAt ?? Date()
            ) { _ in
                let solution = vm.playerMoves.map {
                    "\($0.firstIdx):\($0.secondIdx):\($0.op):\($0.resultLabel)"
                }.joined(separator: ",")
                Task {
                    if await manager.submitToday(solution: solution) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showResults = true
                        }
                        showConfetti = true
                        try? await Task.sleep(for: .seconds(1.35))
                        showConfetti = false
                    }
                }
            }
            isConfigured = true
        }
        .alert("Couldn’t save your solve", isPresented: Binding(
            get: { manager.errorMessage != nil },
            set: { if !$0 { manager.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }
}

private struct DailyConfettiView: View {
    @State private var didPop = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<58, id: \.self) { index in
                    RoundedRectangle(cornerRadius: index.isMultiple(of: 3) ? 5 : 1)
                        .fill(confettiColor(index))
                        .frame(
                            width: index.isMultiple(of: 4) ? 7 : 10,
                            height: index.isMultiple(of: 3) ? 10 : 6
                        )
                        .rotationEffect(.degrees(didPop ? Double(index * 83 + 360) : Double(index * 17)))
                        .position(
                            x: popX(index, size: geometry.size),
                            y: popY(index, size: geometry.size)
                        )
                        .opacity(didPop ? 0 : 1)
                        .animation(
                            .easeOut(duration: 0.9 + Double(index % 5) * 0.08)
                                .delay(Double(index % 8) * 0.018),
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
        let angle = Double(index) / 58 * Double.pi * 2
        let distance = CGFloat(105 + (index * 37) % 145)
        return size.width / 2 + CGFloat(cos(angle)) * distance
    }

    private func popY(_ index: Int, size: CGSize) -> CGFloat {
        let origin = min(size.height * 0.23, 220)
        guard didPop else { return origin }
        let angle = Double(index) / 58 * Double.pi * 2
        let distance = CGFloat(95 + (index * 29) % 125)
        return origin + CGFloat(sin(angle)) * distance + 34
    }

    private func confettiColor(_ index: Int) -> Color {
        if index.isMultiple(of: 5) { return Theme.amber }
        return Theme.cardColors[index % Theme.cardColors.count]
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
            .navigationTitle("Daily Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .foregroundColor(Theme.brown)
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
                    HStack(spacing: 12) {
                        rankLabel(entry.rank)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.schoolKey == "non-school" ? "Non-school" : entry.schoolKey)
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(entry.isCurrentSchool ? Theme.amber.opacity(0.14) : Color.clear)
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
                        Text("@\(entry.username)")
                            .font(.system(size: 16, weight: entry.isCurrentUser ? .bold : .semibold, design: .rounded))
                            .foregroundColor(Theme.brown)
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

struct UniversitySettingsView: View {
    @Bindable var manager: DailyPuzzleManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text("Use your university email so your solve contributes to your school’s daily average.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(Theme.textSecondary)

                    if manager.university.isVerified {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 24))
                                .foregroundColor(Theme.amber)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(manager.university.schoolKey)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                Text(manager.university.email ?? "")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        TextField("name@university.edu", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(15)
                            .background(Theme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        if codeSent {
                            Text("Check your inbox for a verification code or link.")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(Theme.textSecondary)

                            TextField("Verification code", text: $code)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .padding(15)
                                .background(Theme.cream)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }

                        Button {
                            Task {
                                if codeSent {
                                    if await manager.verify(email: email, code: code) { dismiss() }
                                } else if await manager.sendVerification(email: email) {
                                    codeSent = true
                                }
                            }
                        } label: {
                            Text(codeSent ? "Verify Email" : "Send Verification Code")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Theme.buttonPrimary)
                                .foregroundColor(Theme.cardSelectedText)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .disabled(manager.isLoading || (codeSent && code.isEmpty))
                        .buttonStyle(.plain)

                        if codeSent {
                            Button {
                                Task {
                                    if await manager.syncVerifiedEmail() { dismiss() }
                                }
                            } label: {
                                Text("I verified with the email link")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(manager.isLoading)
                            .buttonStyle(.plain)
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
            .navigationTitle("University Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(Theme.brown)
                }
            }
        }
        .task {
            await manager.refreshUniversity()
            email = manager.university.email ?? email
        }
    }
}
