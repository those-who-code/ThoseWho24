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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black.opacity(0.4))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()

            VStack(spacing: 32) {
                // Title
                VStack(spacing: 6) {
                    Text("Multiplayer")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                    Text("Race to make 24")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.black.opacity(0.4))
                }

                // Mode picker
                HStack(spacing: 0) {
                    ForEach([(LobbyMode.create, "Create"), (LobbyMode.join, "Join")], id: \.1) { mode, label in
                        Button {
                            Haptics.selection()
                            withAnimation(.easeOut(duration: 0.15)) { lobbyMode = mode }
                        } label: {
                            Text(label)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .foregroundColor(lobbyMode == mode ? .white : .black.opacity(0.5))
                                .background(lobbyMode == mode ? Color.black : Color.clear)
                        }
                    }
                }
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 32)

                // Input fields
                VStack(spacing: 12) {
                    TextField("Display name", text: $vm.displayName)
                        .font(.system(size: 17, design: .rounded))
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .focused($nameFieldFocused)
                        .submitLabel(.next)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif

                    if lobbyMode == .join {
                        TextField("Room code (e.g. ABC123)", text: $vm.joinCode)
                            .font(.system(size: 17, design: .monospaced))
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                .tint(.white)
                        } else {
                            Text(lobbyMode == .create ? "Create Room" : "Join Room")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
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
