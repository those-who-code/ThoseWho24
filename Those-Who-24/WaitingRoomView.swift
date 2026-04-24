import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Waiting Room View

struct WaitingRoomView: View {
    var vm: MultiplayerViewModel
    let onExit: () -> Void

    @State private var codeCopied = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    Haptics.medium()
                    Task { await vm.leaveRoom() }
                    onExit()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Leave")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Theme.brown.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.cream.opacity(0.7))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 36) {
                // Room code
                VStack(spacing: 10) {
                    Text("Room Code")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textMuted)

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = vm.currentRoom?.code
                        Haptics.light()
                        #elseif canImport(AppKit)
                        if let code = vm.currentRoom?.code {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }
                        #endif
                        withAnimation { codeCopied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { codeCopied = false }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Text(vm.currentRoom?.code ?? "------")
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.brown)
                            Image(systemName: codeCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(codeCopied ? Theme.warmGreen : Theme.amber)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    if codeCopied {
                        Text("Copied!")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.warmGreen)
                            .transition(.opacity)
                    }
                }

                // Players list
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(vm.players.count) player\(vm.players.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(vm.players) { player in
                            HStack {
                                Circle()
                                    .fill(Theme.warmGreen.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(String(player.displayName.prefix(1)).uppercased())
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(Theme.warmGreen)
                                    )

                                Text(player.displayName)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                Spacer()
                                if player.isHost {
                                    Text("Host")
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundColor(Theme.amber)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Theme.amber.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if player.id != vm.players.last?.id {
                                Divider()
                                    .background(Theme.brown.opacity(0.08))
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Theme.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 32)
                }

                // Status text
                if vm.players.count < 2 {
                    HStack(spacing: 6) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                            .tint(Theme.brown.opacity(0.35))
                        Text("Waiting for more players...")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textMuted)
                    }
                }
            }

            Spacer()

            // Start button (host only)
            if vm.isHost {
                Button {
                    Haptics.heavy()
                    Task { await vm.startGame() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Start Game")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(vm.players.count >= 2 ? Theme.buttonPrimary : Theme.buttonSecondary)
                    .foregroundColor(vm.players.count >= 2 ? Theme.cardSelectedText : Theme.brown.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Theme.brown.opacity(vm.players.count >= 2 ? 0.15 : 0), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(vm.players.count < 2)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(Theme.brown.opacity(0.35))
                    Text("Waiting for host to start...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(.bottom, 40)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: vm.players.count)
    }
}
