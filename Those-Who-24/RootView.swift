import SwiftUI

// MARK: - App Mode

enum AppMode: Equatable {
    case singlePlayer
    case multiplayer
    case stats
    case settings
}

// MARK: - Root View

struct RootView: View {
    @State private var mode: AppMode = .singlePlayer
    @State private var mpVM = MultiplayerViewModel()
    @State private var friends = FriendsManager.shared
    @State private var notifications = PushNotificationManager.shared
    @State private var daily = DailyPuzzleManager.shared
    @State private var showDailyPuzzle = false
    @State private var isPreparingDailyPuzzle = false
    @ObservedObject private var themeManager = ThemeManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch mode {
            case .singlePlayer:
                ContentView(
                    onMultiplayerTap: { mode = .multiplayer },
                    onStatsTap: { mode = .stats },
                    onSettingsTap: { mode = .settings },
                    onDailyTap: daily.hasCompletedToday ? nil : {
                        Task { await openDailyPuzzle() }
                    },
                    highlightDailyBanner: daily.isFirstDailyExperience
                )
                .transition(.opacity)
            case .stats:
                StatsView(onBack: { mode = .singlePlayer })
                    .transition(.opacity)
            case .settings:
                SettingsView(onBack: { mode = .singlePlayer })
                    .transition(.opacity)
            case .multiplayer:
                MultiplayerRootView(vm: mpVM) {
                    Task { await mpVM.leaveRoom() }
                    mode = .singlePlayer
                }
                .transition(.opacity)
            }

            if friends.state != .ready {
                SocialGateOverlay(friends: friends)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(themeManager.current.interfaceColorScheme)
        .animation(.easeInOut(duration: 0.2), value: mode)
        .fullScreenCover(isPresented: $showDailyPuzzle) {
            if let puzzle = daily.puzzle {
                DailyPuzzleView(puzzle: puzzle) {
                    showDailyPuzzle = false
                }
            }
        }
        .task {
            await friends.bootstrap()
            if mpVM.displayName.isEmpty, let username = friends.username {
                mpVM.displayName = username
            }
            await joinPendingInviteIfPossible()
            await refreshDailyPuzzleStatus()
        }
        .onChange(of: friends.username) { _, username in
            if mpVM.displayName.isEmpty, let username {
                mpVM.displayName = username
            }
        }
        .onChange(of: friends.state) { _, state in
            guard state == .ready else { return }
            Task {
                await joinPendingInviteIfPossible()
                await refreshDailyPuzzleStatus()
            }
        }
        .onChange(of: notifications.pendingRoomCode) { _, roomCode in
            guard roomCode != nil else { return }
            Task { await joinPendingInviteIfPossible() }
        }
        .onChange(of: notifications.pendingDailyPuzzle) { _, isPending in
            guard isPending else { return }
            Task { await openPendingDailyPuzzleReminder() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshDailyPuzzleStatus() }
        }
    }

    private func refreshDailyPuzzleStatus() async {
        guard friends.state == .ready else { return }
        guard await daily.refreshTodayStatus() else { return }
        await notifications.scheduleDailyPuzzleReminderIfNeeded(
            hasCompletedToday: daily.hasCompletedToday,
            utcDateKey: daily.utcDateKey
        )
        if notifications.pendingDailyPuzzle {
            await openPendingDailyPuzzleReminder()
        }
    }

    private func openPendingDailyPuzzleReminder() async {
        guard friends.state == .ready else { return }
        notifications.consumeDailyPuzzleReminder()
        mode = .singlePlayer
        await openDailyPuzzle()
    }

    private func openDailyPuzzle() async {
        guard !showDailyPuzzle, !isPreparingDailyPuzzle else { return }
        isPreparingDailyPuzzle = true
        defer { isPreparingDailyPuzzle = false }
        if await daily.startToday() != nil {
            showDailyPuzzle = true
        }
    }

    private func joinPendingInviteIfPossible() async {
        guard friends.state == .ready,
              let roomCode = notifications.pendingRoomCode else { return }

        notifications.consumeRoomInvite()
        mode = .multiplayer

        guard mpVM.state == .nameEntry else {
            mpVM.errorMessage = "Leave your current multiplayer room before joining another invite."
            return
        }

        if mpVM.displayName.isEmpty, let username = friends.username {
            mpVM.displayName = username
        }
        mpVM.joinCode = roomCode
        await mpVM.joinRoom()
    }
}

// MARK: - Multiplayer Root

struct MultiplayerRootView: View {
    var vm: MultiplayerViewModel
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            switch vm.state {
            case .nameEntry, .loading:
                LobbyView(vm: vm, onExit: onExit)

            case .waitingRoom:
                WaitingRoomView(vm: vm, onExit: onExit)

            case .playing:
                if let gvm = vm.gameVM {
                    MultiplayerGameView(vm: vm, gameVM: gvm, onExit: onExit)
                }

            case .roundOver(let winnerName, let didWin, let winnerSolution):
                if let gvm = vm.gameVM {
                    MultiplayerGameView(vm: vm, gameVM: gvm, onExit: onExit)
                        .overlay(
                            RoundResultOverlay(
                                winnerName: winnerName,
                                didWin: didWin,
                                winnerSolution: winnerSolution,
                                numbers: vm.currentRoom?.numbers ?? [],
                                solutions: gvm.allSolutions,
                                onReady: { Task { await vm.markReady() } },
                                onExit: {
                                    Task { await vm.leaveRoom() }
                                    onExit()
                                }
                            )
                        )
                }

            case .dissolved(let reason):
                DissolvedView(reason: reason, onDismiss: {
                    vm.dismissError()
                    onExit()
                })
            }

            // Error toast
            if let msg = vm.errorMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.cream)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Theme.brown.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 48)
                        .onTapGesture { vm.dismissError() }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: vm.errorMessage != nil)
            }
        }
    }
}

// MARK: - Shared move type

struct WinnerMove {
    let firstIdx: Int
    let secondIdx: Int
    let op: String
    let result: String
}

// MARK: - Round Result Overlay

struct RoundResultOverlay: View {
    let winnerName: String
    let didWin: Bool
    let winnerSolution: String  // "display|firstIdx:secondIdx:op:result,..." or just "display"
    let numbers: [Int]
    let solutions: [Solution]
    let onReady: () -> Void
    let onExit: () -> Void

    @State private var isReady = false

    private var displayPart: String {
        winnerSolution.components(separatedBy: "|").first ?? winnerSolution
    }

    private var parsedMoves: [WinnerMove] {
        guard let indexPart = winnerSolution.components(separatedBy: "|").dropFirst().first else { return [] }
        return indexPart.components(separatedBy: ",").compactMap { token in
            let parts = token.components(separatedBy: ":")
            guard parts.count >= 4, let f = Int(parts[0]), let s = Int(parts[1]) else { return nil }
            return WinnerMove(firstIdx: f, secondIdx: s, op: parts[2], result: parts[3])
        }
    }

    private var computedExpression: String {
        guard !parsedMoves.isEmpty, numbers.count == 4 else { return displayPart }
        var exprs: [String?] = numbers.map { "\($0)" }
        for m in parsedMoves {
            guard m.firstIdx < exprs.count, m.secondIdx < exprs.count,
                  let a = exprs[m.firstIdx], let b = exprs[m.secondIdx] else { continue }
            exprs[m.secondIdx] = "(\(a) \(m.op) \(b))"
            exprs[m.firstIdx] = nil
        }
        var expr = exprs.compactMap { $0 }.first ?? displayPart
        if expr.hasPrefix("(") && expr.hasSuffix(")") { expr = String(expr.dropFirst().dropLast()) }
        return expr
    }

    var body: some View {
        ZStack {
            Theme.backgroundTop.opacity(0.97).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with back button
                HStack {
                    Button {
                        Haptics.medium()
                        onExit()
                    } label: {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Theme.cream.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Header
                VStack(spacing: 10) {
                    Image(systemName: didWin ? "star.fill" : "clock.badge.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundColor(didWin ? Theme.amber : Theme.textSecondary)

                    Text(didWin ? "You solved it!" : "\(winnerName) was faster")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.brown)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Expression + animated card replay
                if !numbers.isEmpty {
                    Text(computedExpression)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                        .padding(.bottom, 4)

                    Text(didWin ? "Your solution" : "\(winnerName)'s solution")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 48)
                        .padding(.bottom, 6)

                    CardAnimationView(numbers: numbers, moves: parsedMoves)
                        .padding(.horizontal, 48)
                        .padding(.bottom, 20)
                }

                // All solutions
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(solutions.count) solution\(solutions.count == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textMuted)
                            .padding(.horizontal, 32)

                        ForEach(Array(solutions.prefix(50).enumerated()), id: \.offset) { idx, sol in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Solution \(idx + 1)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)

                                Text(sol.expression)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Theme.brown)

                                ForEach(Array(sol.steps.enumerated()), id: \.offset) { _, step in
                                    Text("\(step.a) \(step.op) \(step.b) = \(step.result)")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal, 32)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Ready button
                Button {
                    guard !isReady else { return }
                    isReady = true
                    Haptics.medium()
                    onReady()
                } label: {
                    Text(isReady ? "Waiting for other player..." : "Ready")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundColor(isReady ? Theme.textSecondary : Theme.cardSelectedText)
                        .background(isReady ? Theme.cream : Theme.buttonPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: Theme.brown.opacity(isReady ? 0 : 0.15), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isReady)
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Animated Card Replay

struct CardAnimationView: View {
    let numbers: [Int]
    let moves: [WinnerMove]

    @State private var labels: [String]
    @State private var visible: [Bool] = [true, true, true, true]
    @State private var sourceIdx: Int? = nil
    @State private var destIdx: Int? = nil
    @State private var opLabel: String = ""
    @State private var loopTask: Task<Void, Never>? = nil

    private let cardH: CGFloat = 62
    private let spacing: CGFloat = 10

    init(numbers: [Int], moves: [WinnerMove]) {
        self.numbers = numbers
        self.moves = moves
        _labels = State(initialValue: numbers.map { "\($0)" })
    }

    var body: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) { animCard(0); animCard(1) }
            HStack(spacing: spacing) { animCard(2); animCard(3) }
        }
        .onAppear { startLoop() }
        .onDisappear { loopTask?.cancel() }
    }

    @ViewBuilder
    private func animCard(_ i: Int) -> some View {
        let isSrc = sourceIdx == i
        let isDst = destIdx == i
        let lbl = labels.indices.contains(i) ? labels[i] : "\(numbers.indices.contains(i) ? numbers[i] : 0)"
        let vis = visible.indices.contains(i) ? visible[i] : true

        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14)
                .fill(isSrc ? Theme.buttonPrimary : Theme.cardColors[i % Theme.cardColors.count])
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.buttonPrimary, lineWidth: isDst ? 2.5 : 0)
                )

            Text(lbl)
                .id(lbl)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(isSrc ? Theme.cardSelectedText : Theme.brown)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: cardH)

            if isSrc && !opLabel.isEmpty {
                Text(opLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.cardSelectedText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.brown.opacity(0.35))
                    .clipShape(Capsule())
                    .padding(5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardH)
        .scaleEffect(isSrc ? 1.07 : 1.0)
        .opacity(vis ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSrc)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDst)
        .animation(.easeOut(duration: 0.35), value: vis)
    }

    private func startLoop() {
        guard !moves.isEmpty else { return }
        loopTask?.cancel()
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                // Reset to original state
                withAnimation(.easeInOut(duration: 0.3)) {
                    labels = numbers.map { "\($0)" }
                    visible = [true, true, true, true]
                    sourceIdx = nil
                    destIdx = nil
                    opLabel = ""
                }
                try? await Task.sleep(nanoseconds: 500_000_000)

                for move in moves {
                    guard !Task.isCancelled else { return }

                    // Phase 1: highlight both cards + show op badge
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        sourceIdx = move.firstIdx
                        destIdx = move.secondIdx
                        opLabel = move.op
                    }
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    guard !Task.isCancelled else { return }

                    // Phase 2: source card fades out, destination updates to result
                    withAnimation(.easeInOut(duration: 0.35)) {
                        visible[move.firstIdx] = false
                        labels[move.secondIdx] = move.result
                        sourceIdx = nil
                        destIdx = nil
                        opLabel = ""
                    }
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }

                // Hold on final state before looping
                try? await Task.sleep(nanoseconds: 1_400_000_000)
            }
        }
    }
}

// MARK: - Dissolved View

struct DissolvedView: View {
    let reason: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 36))
                .foregroundColor(Theme.warmGreen)

            Text(reason)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Back to Menu") {
                Haptics.medium()
                onDismiss()
            }
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Theme.buttonPrimary)
            .foregroundColor(Theme.cardSelectedText)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.horizontal, 40)
        }
    }
}
