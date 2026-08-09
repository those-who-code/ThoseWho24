import Foundation
import SwiftUI

enum SocialBootstrapState: Equatable {
    case loading
    case needsUsername(isLegacyInstall: Bool)
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
    private let cachedUsernameKey = "cachedUsername"
    private var subscriptionTask: Task<Void, Never>?
    private var didBootstrap = false

    private init() {
        username = UserDefaults.standard.string(forKey: cachedUsernameKey)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        let defaults = UserDefaults.standard
        let wasLegacyInstall =
            defaults.object(forKey: "selectedTheme") != nil ||
            defaults.object(forKey: "solveRecords") != nil

        do {
            let id = try await service.ensureAnonymousSession()
            userId = id
            let profile = try await service.fetchProfile(userId: id)
            if let fetchedUsername = profile?.username, !fetchedUsername.isEmpty {
                username = fetchedUsername
                cacheUsername(fetchedUsername)
                state = .ready
                await refreshConnections()
                startSubscription()
                PushNotificationManager.shared.requestAuthorizationAndRegister()
                await registerPendingDeviceToken()
            } else {
                username = nil
                UserDefaults.standard.removeObject(forKey: cachedUsernameKey)
                state = .needsUsername(isLegacyInstall: wasLegacyInstall)
            }
        } catch {
            state = .failed(friendlyMessage(for: error))
        }
    }

    func retryBootstrap() async {
        didBootstrap = false
        state = .loading
        await bootstrap()
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

        do {
            let profile = try await service.setUsername(normalized)
            guard let savedUsername = profile.username, !savedUsername.isEmpty else {
                errorMessage = "Your username could not be saved. Please try again."
                return false
            }
            username = savedUsername
            cacheUsername(savedUsername)
            UserDefaults.standard.set(true, forKey: "completedUsernameOnboarding")
            state = .ready
            await refreshConnections()
            startSubscription()
            PushNotificationManager.shared.requestAuthorizationAndRegister()
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

    private func cacheUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: cachedUsernameKey)
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
