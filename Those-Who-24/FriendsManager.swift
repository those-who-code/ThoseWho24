import Foundation
import SwiftUI
import Supabase

enum SocialBootstrapState: Equatable {
    case loading
    case needsAppleSignIn
    case needsAppleMigration(username: String)
    case needsUsername
    case ready
    case failed(String)
}

@Observable
@MainActor
final class FriendsManager {
    static let shared = FriendsManager()

    private(set) var state: SocialBootstrapState = .loading
    private(set) var userId: UUID?
    private(set) var username: String?
    private(set) var connections: [FriendConnectionRow] = []
    private(set) var searchResults: [FriendSearchResult] = []
    private(set) var isSearching = false
    private(set) var isSavingUsername = false
    private(set) var isAuthenticatingWithApple = false
    private(set) var isDeletingAccount = false
    private(set) var isAppleBacked = false
    private(set) var isOffline = false
    private(set) var isAdmin = false
    var errorMessage: String?

    var friends: [FriendConnectionRow] {
        connections.filter { $0.status == "accepted" }
    }

    var incomingRequests: [FriendConnectionRow] {
        connections.filter { $0.status == "pending" && $0.isIncoming }
    }

    var outgoingRequests: [FriendConnectionRow] {
        connections.filter { $0.status == "pending" && !$0.isIncoming }
    }

    var pendingRequestCount: Int { incomingRequests.count }

    private let service = SupabaseService.shared
    private var subscriptionTask: Task<Void, Never>?
    private var didBootstrap = false
    private let cachedUserIdKey = "cachedSocialUserId"
    private let cachedUsernameKey = "cachedSocialUsername"
    private let cachedAnonymousKey = "cachedSocialUserWasAnonymous"

    private init() {}

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        guard service.cachedUser != nil else {
            state = .needsAppleSignIn
            return
        }

        do {
            let user = try await service.validatedUser()
            try await configureAuthenticatedUser(user)
        } catch {
            // A network failure must never destroy an otherwise recoverable
            // session. Use the last server-confirmed profile for offline play.
            let defaults = UserDefaults.standard
            if let idString = defaults.string(forKey: cachedUserIdKey),
               let id = UUID(uuidString: idString),
               let cachedUsername = defaults.string(forKey: cachedUsernameKey) {
                userId = id
                username = cachedUsername
                isAppleBacked = !defaults.bool(forKey: cachedAnonymousKey)
                isOffline = true
                state = .ready
            } else {
                state = .failed(friendlyMessage(for: error))
            }
        }
    }

    func retryBootstrap() async {
        didBootstrap = false
        state = .loading
        await bootstrap()
    }

    func continueWithApple(idToken: String, nonce: String, linkCurrentAccount: Bool) async {
        guard !isAuthenticatingWithApple else { return }
        isAuthenticatingWithApple = true
        errorMessage = nil
        defer { isAuthenticatingWithApple = false }
        do {
            let user = try await (linkCurrentAccount
                ? service.linkAppleIdentity(idToken: idToken, nonce: nonce)
                : service.signInWithApple(idToken: idToken, nonce: nonce))
            try await configureAuthenticatedUser(user)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func configureAuthenticatedUser(_ user: User) async throws {
        let profile = try await service.fetchProfile(userId: user.id)
        userId = user.id
        username = profile?.username
        isAppleBacked = !user.isAnonymous
        isOffline = false
        cacheProfile(userId: user.id, username: profile?.username, isAnonymous: user.isAnonymous)

        if user.isAnonymous, let username = profile?.username, !username.isEmpty {
            state = .needsAppleMigration(username: username)
        } else if user.isAnonymous {
            state = .needsAppleSignIn
        } else if profile?.username?.isEmpty != false {
            state = .needsUsername
        } else {
            await becomeReady()
        }
    }

    private func becomeReady() async {
        state = .ready
        await refreshConnections()
        startSubscription()
        PushNotificationManager.shared.requestAuthorizationAndRegister()
        await registerPendingDeviceToken()
        isAdmin = (try? await service.isRecoveryAdmin()) ?? false
        await syncDailyCompletionHistory()
        await RecoveryManager.shared.refreshMine()
    }

    private func cacheProfile(userId: UUID, username: String?, isAnonymous: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(userId.uuidString, forKey: cachedUserIdKey)
        defaults.set(username, forKey: cachedUsernameKey)
        defaults.set(isAnonymous, forKey: cachedAnonymousKey)
    }

    private func syncDailyCompletionHistory() async {
        if let dates = try? await service.fetchDailyCompletionDates() {
            StatsManager.shared.mergeServerDailyCompletionDates(dates)
        }
    }

    func leaveAnonymousMigration() async {
        guard case .needsAppleMigration = state, !isAuthenticatingWithApple else { return }
        subscriptionTask?.cancel()
        subscriptionTask = nil
        await service.signOutLocally()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: cachedUserIdKey)
        defaults.removeObject(forKey: cachedUsernameKey)
        defaults.removeObject(forKey: cachedAnonymousKey)
        userId = nil
        username = nil
        connections = []
        searchResults = []
        isAppleBacked = false
        isOffline = false
        isAdmin = false
        errorMessage = nil
        state = .needsAppleSignIn
    }

    func createUsername(_ rawUsername: String) async -> Bool {
        let normalized = rawUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalized.range(
            of: #"^[a-z0-9_]{3,20}$"#,
            options: .regularExpression
        ) != nil else {
            errorMessage = "Use 3–20 letters, numbers, or underscores."
            return false
        }

        isSavingUsername = true
        errorMessage = nil
        defer { isSavingUsername = false }

        guard isAppleBacked else {
            errorMessage = "Sign in with Apple before creating a username."
            return false
        }

        do {
            let profile = try await service.setUsername(normalized)
            guard let savedUsername = profile.username, !savedUsername.isEmpty else {
                errorMessage = "Your username could not be saved. Please try again."
                return false
            }
            username = savedUsername
            cacheProfile(userId: profile.id, username: savedUsername, isAnonymous: false)
            UserDefaults.standard.set(true, forKey: "completedUsernameOnboarding")
            await becomeReady()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func didCompleteRecovery(_ profile: ProfileRow) async {
        userId = profile.id
        username = profile.username
        isAppleBacked = true
        cacheProfile(userId: profile.id, username: profile.username, isAnonymous: false)
        await becomeReady()
    }

    func deleteAccount() async -> Bool {
        guard userId != nil, !isDeletingAccount else { return false }
        guard !isOffline else {
            errorMessage = "Connect to the internet before deleting your account."
            return false
        }

        isDeletingAccount = true
        errorMessage = nil
        defer { isDeletingAccount = false }

        do {
            try await service.deleteMyAccount()
            subscriptionTask?.cancel()
            subscriptionTask = nil

            let defaults = UserDefaults.standard
            [
                cachedUserIdKey,
                cachedUsernameKey,
                cachedAnonymousKey,
                "completedUsernameOnboarding",
                "hasCompletedFirstDailyPuzzle",
                "dailyPuzzleSolutionDate",
                "dailyPuzzleSolutionMoves",
                "pendingDailyPuzzleSubmissionDate",
                "pendingDailyPuzzleSubmissionMoves",
                "cachedUniversitySchoolKey",
                "scheduledDailyPuzzleReminderUTC"
            ].forEach { defaults.removeObject(forKey: $0) }

            StatsManager.shared.reset()
            PushNotificationManager.shared.cancelDailyPuzzleReminder()
            PushNotificationManager.shared.consumeRoomInvite()
            PushNotificationManager.shared.consumeDailyPuzzleReminder()
            PushNotificationManager.shared.consumeFriendRequests()

            userId = nil
            username = nil
            connections = []
            searchResults = []
            isAppleBacked = false
            isOffline = false
            isAdmin = false
            didBootstrap = true
            state = .needsAppleSignIn
            UIApplication.shared.applicationIconBadgeNumber = 0
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func refreshConnections() async {
        do {
            connections = try await service.fetchFriendConnections()
            UIApplication.shared.applicationIconBadgeNumber = pendingRequestCount
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func search(_ query: String) async {
        let normalized = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await service.searchProfiles(query: normalized)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func sendRequest(to result: FriendSearchResult) async {
        errorMessage = nil
        do {
            let requestId = try await service.sendFriendRequest(to: result.userId)
            updateSearchState(userId: result.userId, state: "outgoing")
            await refreshConnections()
            await service.sendFriendNotification(
                requestId: requestId,
                kind: "request_received"
            )
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func respond(to request: FriendConnectionRow, accept: Bool) async {
        errorMessage = nil
        do {
            try await service.respondToFriendRequest(id: request.requestId, accept: accept)
            await refreshConnections()
            if accept {
                await service.sendFriendNotification(
                    requestId: request.requestId,
                    kind: "request_accepted"
                )
            }
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func remove(_ connection: FriendConnectionRow) async {
        errorMessage = nil
        do {
            try await service.removeFriendConnection(userId: connection.userId)
            updateSearchState(userId: connection.userId, state: "none")
            await refreshConnections()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func registerPendingDeviceToken() async {
        guard let token = PushNotificationManager.shared.deviceToken,
              userId != nil else { return }
        do {
            try await service.registerDeviceToken(
                token,
                environment: PushNotificationManager.apnsEnvironment
            )
        } catch {
            // Token registration will retry on the next successful app launch.
        }
    }

    private func updateSearchState(userId: UUID, state: String) {
        guard let index = searchResults.firstIndex(where: { $0.userId == userId }) else { return }
        searchResults[index].relationshipState = state
    }

    private func startSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = service.subscribeToFriendChanges { [weak self] in
            Task { @MainActor [weak self] in
                await self?.refreshConnections()
            }
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("already taken") ||
            message.localizedCaseInsensitiveContains("duplicate") {
            return "That username is already taken."
        }
        return message
    }
}
