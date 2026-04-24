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
                            .font(.system(size: 14, weight: .medium))
                        Text("Leave")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.black.opacity(0.4))
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 36) {
                // Room code
                VStack(spacing: 8) {
                    Text("Room Code")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.35))

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
                        HStack(spacing: 8) {
                            Text(vm.currentRoom?.code ?? "------")
                                .font(.system(size: 36, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.black.opacity(0.3))
                        }
                    }

                    if codeCopied {
                        Text("Copied!")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.black.opacity(0.35))
                            .transition(.opacity)
                    }
                }

                // Players list
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(vm.players.count) player\(vm.players.count == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.35))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    VStack(spacing: 0) {
                        ForEach(vm.players) { player in
                            HStack {
                                Text(player.displayName)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundColor(.black)
                                Spacer()
                                if player.isHost {
                                    Text("Host")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.black.opacity(0.35))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            if player.id != vm.players.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)
                }

                // Status text
                if vm.players.count < 2 {
                    Text("Waiting for more players...")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.black.opacity(0.35))
                }
            }

            Spacer()

            // Start button (host only)
            if vm.isHost {
                Button {
                    Haptics.heavy()
                    Task { await vm.startGame() }
                } label: {
                    Text("Start Game")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(vm.players.count >= 2 ? Color.black : Color.black.opacity(0.1))
                        .foregroundColor(vm.players.count >= 2 ? .white : .black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(vm.players.count < 2)
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            } else {
                Text("Waiting for host to start...")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.black.opacity(0.35))
                    .padding(.bottom, 40)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.players.count)
    }
}
