import SwiftUI

// MARK: - Lobby Mode

private enum LobbyMode {
    case create, join
}

// MARK: - Lobby View

struct LobbyView: View {
    @Bindable var vm: MultiplayerViewModel
    let onExit: () -> Void

    @State private var lobbyMode: LobbyMode = .create
    @FocusState private var nameFieldFocused: Bool

    var isLoading: Bool { vm.state == .loading }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    Haptics.light()
                    onExit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.brown.opacity(0.5))
                        .frame(width: 32, height: 32)
                        .background(Theme.cream.opacity(0.7))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 32) {
                // Title
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.amber)
                        Text("Multiplayer")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.brown)
                    }
                    Text("Race to make 24")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }

                // Mode picker
                HStack(spacing: 4) {
                    ForEach([(LobbyMode.create, "Create"), (LobbyMode.join, "Join")], id: \.1) { mode, label in
                        Button {
                            Haptics.selection()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { lobbyMode = mode }
                        } label: {
                            Text(label)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .foregroundColor(lobbyMode == mode ? Theme.cardSelectedText : Theme.brown.opacity(0.5))
                                .contentShape(Rectangle())
                                .background(lobbyMode == mode ? Theme.buttonPrimary : Color.white.opacity(0.001))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Theme.cream)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 32)

                // Input fields
                VStack(spacing: 12) {
                    TextField("Display name", text: $vm.displayName)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.brown)
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Theme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .focused($nameFieldFocused)
                        .submitLabel(.next)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    if lobbyMode == .join {
                        TextField("Room code (e.g. ABC123)", text: $vm.joinCode)
                            .font(.system(size: 17, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.brown)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(Theme.cream)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .onChange(of: vm.joinCode) { _, new in
                                if new.count > 6 { vm.joinCode = String(new.prefix(6)) }
                            }
                            .submitLabel(.go)
                            .onSubmit { performAction() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 32)
                .animation(.easeOut(duration: 0.2), value: lobbyMode)

                // Action button
                Button {
                    Haptics.medium()
                    nameFieldFocused = false
                    performAction()
                } label: {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.cardSelectedText)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: lobbyMode == .create ? "plus.circle.fill" : "arrow.right.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                Text(lobbyMode == .create ? "Create Room" : "Join Room")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(Theme.cardSelectedText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Theme.buttonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Theme.brown.opacity(0.15), radius: 6, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }

    private func performAction() {
        Task {
            if lobbyMode == .create {
                await vm.createRoom()
            } else {
                await vm.joinRoom()
            }
        }
    }
}
