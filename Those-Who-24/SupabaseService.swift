import Supabase
import Foundation

// MARK: - Supabase Service

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: .init(
                auth: .init(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Room Code Generation

    private func generateCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    // MARK: - Create Room

    func createRoom(displayName: String) async throws -> (room: RoomRow, player: PlayerRow) {
        let playerId = UUID()
        let hostUserId = try await ensureAnonymousSession()

        // Try inserting room with generated code; retry on unique conflict
        var room: RoomRow?
        for _ in 0..<10 {
            let code = generateCode()
            do {
                room = try await client.from("rooms")
                    .insert(RoomInsert(
                        code: code,
                        hostId: playerId.uuidString,
                        hostUserId: hostUserId
                    ))
                    .select()
                    .single()
                    .execute()
                    .value
                break
            } catch {
                // Likely unique constraint violation — try new code
                continue
            }
        }
        guard let room else { throw MultiplayerError.roomCreationFailed }

        let player: PlayerRow = try await client.from("players")
            .insert(PlayerInsert(id: playerId.uuidString,
                                 roomId: room.id.uuidString,
                                 displayName: displayName,
                                 isHost: true))
            .select()
            .single()
            .execute()
            .value

        return (room, player)
    }

    // MARK: - Join Room

    func joinRoom(code: String, displayName: String) async throws -> (room: RoomRow, player: PlayerRow) {
        let rooms: [RoomRow] = try await client.from("rooms")
            .select()
            .eq("code", value: code.uppercased())
            .eq("status", value: "waiting")
            .limit(1)
            .execute()
            .value

        guard let room = rooms.first else {
            throw MultiplayerError.roomNotFound
        }

        let playerId = UUID()
        let player: PlayerRow = try await client.from("players")
            .insert(PlayerInsert(id: playerId.uuidString,
                                 roomId: room.id.uuidString,
                                 displayName: displayName,
                                 isHost: false))
            .select()
            .single()
            .execute()
            .value

        return (room, player)
    }

    // MARK: - Leave Room

    func leaveRoom(playerId: UUID, roomId: UUID, isHost: Bool) async throws {
        if isHost {
            try await client.rpc("dissolve_room",
                                 params: DissolveRoomParams(pRoomId: roomId, pHostId: playerId))
                .execute()
        } else {
            try await client.from("players")
                .delete()
                .eq("id", value: playerId.uuidString)
                .execute()
        }
    }

    // MARK: - Fetch Players

    func fetchPlayers(roomId: UUID) async throws -> [PlayerRow] {
        try await client.from("players")
            .select()
            .eq("room_id", value: roomId.uuidString)
            .order("joined_at")
            .execute()
            .value
    }

    // MARK: - Fetch Room

    func fetchRoom(roomId: UUID) async throws -> RoomRow {
        try await client.from("rooms")
            .select()
            .eq("id", value: roomId.uuidString)
            .single()
            .execute()
            .value
    }

    // MARK: - Start Round (host only)

    func startRound(roomId: UUID, hostPlayerId: UUID, numbers: [Int]) async throws {
        try await client.rpc("start_round",
                             params: StartRoundParams(pRoomId: roomId,
                                                      pHostPlayerId: hostPlayerId,
                                                      pNumbers: numbers))
            .execute()
    }

    // MARK: - Submit Solution

    func submitSolution(roomId: UUID, playerId: UUID, round: Int, solution: String) async throws -> Bool {
        let won: Bool = try await client.rpc("claim_round_win",
                                             params: ClaimWinParams(pRoomId: roomId,
                                                                     pPlayerId: playerId,
                                                                     pRound: round,
                                                                     pSolution: solution))
            .execute()
            .value
        return won
    }

    // MARK: - Realtime Subscriptions

    /// Starts Postgres Change listeners for a room. Calls the provided callbacks on the main actor.
    /// Returns a Task — cancel it to unsubscribe.
    func subscribe(
        roomId: UUID,
        onRoomUpdate: @escaping @Sendable (RoomRow) -> Void,
        onPlayersChange: @escaping @Sendable () -> Void,
        onSubmission: @escaping @Sendable (SubmissionRow) -> Void
    ) -> Task<Void, Never> {
        Task {
            let channel = client.realtimeV2.channel("room-\(roomId)")

            let roomUpdates = channel.postgresChange(
                UpdateAction.self, schema: "public", table: "rooms",
                filter: .eq("id", value: roomId.uuidString))
            let playerChanges = channel.postgresChange(
                AnyAction.self, schema: "public", table: "players",
                filter: .eq("room_id", value: roomId.uuidString))
            let submissionInserts = channel.postgresChange(
                InsertAction.self, schema: "public", table: "submissions",
                filter: .eq("room_id", value: roomId.uuidString))

            try? await channel.subscribeWithError()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await action in roomUpdates {
                        guard !Task.isCancelled else { break }
                        if let room = try? action.decodeRecord(as: RoomRow.self, decoder: JSONDecoder()) {
                            await MainActor.run { onRoomUpdate(room) }
                        }
                    }
                }
                group.addTask {
                    for await _ in playerChanges {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { onPlayersChange() }
                    }
                }
                group.addTask {
                    for await action in submissionInserts {
                        guard !Task.isCancelled else { break }
                        if let submission = try? action.decodeRecord(as: SubmissionRow.self, decoder: JSONDecoder()) {
                            await MainActor.run { onSubmission(submission) }
                        }
                    }
                }
            }

            await client.realtimeV2.removeChannel(channel)
        }
    }

    // MARK: - Ready Signal

    func markReady(playerId: UUID, round: Int) async throws {
        try await client.from("players")
            .update(["ready_round": round])
            .eq("id", value: playerId.uuidString)
            .execute()
    }

    // MARK: - Heartbeat

    func pingPlayer(playerId: UUID) async {
        _ = try? await client.from("players")
            .update(["last_ping": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: playerId.uuidString)
            .execute()
    }

    // MARK: - Identity

    func ensureAnonymousSession() async throws -> UUID {
        if client.auth.currentUser != nil {
            do {
                return try await client.auth.session.user.id
            } catch {
                try? await client.auth.signOut()
            }
        }
        return try await client.auth.signInAnonymously().user.id
    }

    func fetchProfile(userId: UUID) async throws -> ProfileRow? {
        let profiles: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }

    func setUsername(_ username: String) async throws -> ProfileRow {
        try await client.rpc("set_username", params: UsernameParams(username: username))
            .execute()
            .value
    }

    // MARK: - Daily Puzzle

    func startDailyPuzzle() async throws -> DailyPuzzleState {
        try await client.rpc("start_daily_puzzle")
            .execute()
            .value
    }

    func fetchDailyPuzzleStatus() async throws -> DailyPuzzleState {
        try await client.rpc("get_daily_puzzle_status")
            .execute()
            .value
    }

    func submitDailyPuzzle(puzzleDate: String) async throws -> Int {
        try await client.rpc(
            "submit_daily_puzzle",
            params: SubmitDailyPuzzleParams(puzzleDate: puzzleDate)
        )
        .execute()
        .value
    }

    func fetchSchoolDailyLeaderboard(puzzleDate: String? = nil) async throws -> [SchoolDailyLeaderboardEntry] {
        try await client.rpc(
            "daily_school_averages",
            params: DailyLeaderboardParams(puzzleDate: puzzleDate)
        )
        .execute()
        .value
    }

    func fetchFriendsDailyLeaderboard(puzzleDate: String? = nil) async throws -> [DailyLeaderboardEntry] {
        try await client.rpc(
            "daily_friends_leaderboard",
            params: DailyLeaderboardParams(puzzleDate: puzzleDate)
        )
        .execute()
        .value
    }

    func fetchSchoolMembersDailyLeaderboard(
        schoolKey: String,
        puzzleDate: String? = nil
    ) async throws -> [DailyLeaderboardEntry] {
        try await client.rpc(
            "daily_school_members_leaderboard",
            params: SchoolDailyLeaderboardParams(
                schoolKey: schoolKey,
                puzzleDate: puzzleDate
            )
        )
        .execute()
        .value
    }

    func fetchUniversityStatus() async throws -> UniversityStatus {
        try await client.rpc("get_university_status")
            .execute()
            .value
    }

    func selectUniversity(_ schoolKey: String) async throws -> UniversityStatus {
        try await client.rpc(
            "set_university",
            params: SetUniversityParams(schoolKey: schoolKey)
        )
            .execute()
            .value
    }

    // MARK: - Friends

    func searchProfiles(query: String) async throws -> [FriendSearchResult] {
        try await client.rpc("search_profiles", params: SearchProfilesParams(query: query))
            .execute()
            .value
    }

    func fetchFriendConnections() async throws -> [FriendConnectionRow] {
        try await client.rpc("list_friend_connections")
            .execute()
            .value
    }

    func sendFriendRequest(to userId: UUID) async throws -> UUID {
        try await client.rpc(
            "send_friend_request",
            params: FriendRequestParams(receiverId: userId)
        )
        .execute()
        .value
    }

    func respondToFriendRequest(id: UUID, accept: Bool) async throws {
        try await client.rpc(
            "respond_to_friend_request",
            params: FriendResponseParams(requestId: id, accept: accept)
        )
        .execute()
    }

    func removeFriendConnection(userId: UUID) async throws {
        try await client.rpc(
            "remove_friend_connection",
            params: FriendUserParams(userId: userId)
        )
        .execute()
    }

    func registerDeviceToken(_ token: String, environment: String) async throws {
        try await client.rpc(
            "register_device_token",
            params: RegisterDeviceTokenParams(
                token: token,
                environment: environment
            )
        )
        .execute()
    }

    func sendFriendNotification(requestId: UUID, kind: String) async {
        try? await client.functions.invoke(
            "send-friend-notification",
            options: .init(
                body: FriendNotificationBody(requestId: requestId, kind: kind)
            )
        )
    }

    func sendRoomInvite(to recipientId: UUID, roomCode: String) async throws {
        try await client.functions.invoke(
            "send-friend-notification",
            options: .init(
                body: RoomInviteNotificationBody(
                    recipientId: recipientId,
                    roomCode: roomCode
                )
            )
        )
    }

    func sendDailySolveNotification() async {
        try? await client.functions.invoke(
            "send-friend-notification",
            options: .init(body: DailySolveNotificationBody())
        )
    }

    func subscribeToFriendChanges(onChange: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        Task {
            let channel = client.realtimeV2.channel("friend-connections")
            let changes = channel.postgresChange(
                AnyAction.self,
                schema: "public",
                table: "friend_connections"
            )

            try? await channel.subscribeWithError()
            for await _ in changes {
                guard !Task.isCancelled else { break }
                await MainActor.run { onChange() }
            }
            await client.realtimeV2.removeChannel(channel)
        }
    }
}

// MARK: - Errors

enum MultiplayerError: LocalizedError {
    case roomCreationFailed
    case roomNotFound
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .roomCreationFailed: return "Failed to create room. Please try again."
        case .roomNotFound:       return "Room not found or already started."
        case .notAuthorized:      return "Not authorized."
        }
    }
}
