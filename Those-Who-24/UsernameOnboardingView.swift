import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

struct SocialGateOverlay: View {
    @Bindable var friends: FriendsManager
    @State private var showRecovery = false
    @State private var showMigrationExitConfirmation = false

    var body: some View {
        switch friends.state {
        case .loading:
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ProgressView()
                    .tint(Theme.amber)
                    .scaleEffect(1.2)
            }

        case .needsAppleSignIn:
            appleCard(
                title: "Sign in to Those Who 24",
                message: "Sign in with Apple keeps your username, friends, and daily history available after reinstalling.",
                linkCurrentAccount: false
            )

        case .needsAppleMigration(let username):
            appleCard(
                title: "Protect @\(username)",
                message: "We found an issue that could disconnect profiles after offline use. Link Apple now to keep this account and its friends.",
                linkCurrentAccount: true
            )

        case .needsUsername:
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 14) {
                    usernameCard(
                        title: "Choose your username",
                        message: "Create a new username, or recover one you previously used."
                    )
                    Button("Recover a previous account") { showRecovery = true }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.brown)
                }
                .padding(.horizontal, 28)
            }
            .sheet(isPresented: $showRecovery) { RecoveryCenterView() }

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

    private func appleCard(title: String, message: String, linkCurrentAccount: Bool) -> some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 38))
                    .foregroundColor(Theme.amber)
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                AppleAuthButton(
                    isLoading: friends.isAuthenticatingWithApple,
                    linkCurrentAccount: linkCurrentAccount,
                    friends: friends
                )
                if let error = friends.errorMessage {
                    Text(error)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.destructiveText)
                        .multilineTextAlignment(.center)
                }
                if linkCurrentAccount {
                    Button("Sign in to an existing account") {
                        showMigrationExitConfirmation = true
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                }
                Button("I lost a previous username") { showRecovery = true }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .disabled(!friends.isAppleBacked)
            }
            .padding(26)
            .background(Theme.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: Color.black.opacity(0.16), radius: 24, y: 10)
            .padding(.horizontal, 28)
        }
        .sheet(isPresented: $showRecovery) { RecoveryCenterView() }
        .confirmationDialog(
            "Leave @\(friends.username ?? "this profile")?",
            isPresented: $showMigrationExitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign In to Existing Account", role: .destructive) {
                Task { await friends.leaveAnonymousMigration() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This profile will remain on the server and can be recovered after you sign in. Nothing is deleted.")
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

private struct AppleAuthButton: View {
    let isLoading: Bool
    let linkCurrentAccount: Bool
    let friends: FriendsManager
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            let nonce = Self.randomNonce()
            rawNonce = nonce
            request.requestedScopes = [.email]
            request.nonce = Self.sha256(nonce)
        } onCompletion: { result in
            guard !isLoading else { return }
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8),
                      let rawNonce else {
                    friends.errorMessage = "Apple did not return a usable identity token. Please try again."
                    return
                }
                Task {
                    await friends.continueWithApple(
                        idToken: idToken,
                        nonce: rawNonce,
                        linkCurrentAccount: linkCurrentAccount
                    )
                }
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    friends.errorMessage = error.localizedDescription
                }
            }
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .disabled(isLoading)
        .overlay {
            if isLoading {
                RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.72))
                ProgressView().tint(.white)
            }
        }
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            guard SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess else {
                return UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            if random < charset.count * (256 / charset.count) {
                result.append(charset[Int(random) % charset.count])
                remaining -= 1
            }
        }
        return result
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
