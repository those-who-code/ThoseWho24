import SwiftUI

struct SocialGateOverlay: View {
    @Bindable var friends: FriendsManager

    var body: some View {
        switch friends.state {
        case .loading:
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ProgressView()
                    .tint(Theme.amber)
                    .scaleEffect(1.2)
            }

        case .needsUsername(let isLegacyInstall):
            if isLegacyInstall {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    usernameCard(
                        title: "Friends are here!",
                        message: "Choose a unique username to connect and play with friends."
                    )
                    .padding(.horizontal, 28)
                }
            } else {
                ZStack {
                    Theme.backgroundGradient.ignoresSafeArea()
                    usernameCard(
                        title: "Choose your username",
                        message: "This is how friends will find you. You can keep playing under any display name."
                    )
                    .padding(.horizontal, 28)
                }
            }

        case .failed(let message):
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundColor(Theme.amber)
                    Text("Couldn't set up your profile")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.brown)
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await friends.retryBootstrap() }
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cardSelectedText)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(Theme.buttonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .buttonStyle(.plain)
                }
                .padding(28)
            }

        case .ready:
            EmptyView()
        }
    }

    private func usernameCard(title: String, message: String) -> some View {
        UsernameForm(
            title: title,
            message: message,
            isSaving: friends.isSavingUsername,
            errorMessage: friends.errorMessage
        ) { username in
            await friends.createUsername(username)
        }
        .padding(26)
        .background(Theme.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
    }
}

private struct UsernameForm: View {
    let title: String
    let message: String
    let isSaving: Bool
    let errorMessage: String?
    let onSubmit: (String) async -> Bool

    @State private var username = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.badge.plus.fill")
                .font(.system(size: 36))
                .foregroundColor(Theme.amber)

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 4) {
                Text("@")
                    .foregroundColor(Theme.textMuted)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit { submit() }
                    .onChange(of: username) { _, value in
                        username = String(
                            value.lowercased().filter {
                                $0.isLetter || $0.isNumber || $0 == "_"
                            }.prefix(20)
                        )
                    }
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(Theme.brown)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.destructiveText)
                    .multilineTextAlignment(.center)
            } else {
                Text("3–20 characters · letters, numbers, and underscores")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textMuted)
            }

            Button {
                submit()
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Theme.cardSelectedText)
                    } else {
                        Text("Create Username")
                    }
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Theme.cardSelectedText)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.buttonPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(isSaving || username.count < 3)
            .opacity(username.count < 3 ? 0.55 : 1)
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !isSaving, username.count >= 3 else { return }
        Task {
            if await onSubmit(username) {
                Haptics.successDoubleTap()
            }
        }
    }
}
