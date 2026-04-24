import SwiftUI

// MARK: - App Mode

enum AppMode {
    case singlePlayer
    case multiplayer
    case stats
}

// MARK: - Root View

struct RootView: View {
    @State private var mode: AppMode = .singlePlayer
    @State private var mpVM = MultiplayerViewModel()

    var body: some View {
        ZStack {
            switch mode {
            case .singlePlayer:
                ContentView(
                    onMultiplayerTap: { mode = .multiplayer },
                    onStatsTap: { mode = .stats }
                )
                .transition(.opacity)
            case .stats:
                StatsView(onBack: { mode = .singlePlayer })
                    .transition(.opacity)
            case .multiplayer:
                MultiplayerRootView(vm: mpVM) {
                    Task { await mpVM.leaveRoom() }
                    mode = .singlePlayer
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
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

            case .roundOver(let winnerName, let didWin):
                if let gvm = vm.gameVM {
                    MultiplayerGameView(vm: vm, gameVM: gvm, onExit: onExit)
                        .overlay(
                            RoundResultOverlay(winnerName: winnerName, didWin: didWin)
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

// MARK: - Round Result Overlay

struct RoundResultOverlay: View {
    let winnerName: String
    let didWin: Bool

    var body: some View {
        ZStack {
            Theme.backgroundTop.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: didWin ? "star.fill" : "clock.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundColor(didWin ? Theme.amber : Theme.brown.opacity(0.4))

                Text(didWin ? "You solved it!" : "\(winnerName) was faster")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .multilineTextAlignment(.center)

                if !didWin {
                    Text("Next round coming up...")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .padding(40)
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
                .foregroundColor(Theme.warmGreen.opacity(0.5))

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
