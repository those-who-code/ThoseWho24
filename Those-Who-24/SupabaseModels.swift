import Foundation

// MARK: - DB Row Models

struct RoomRow: Codable, Identifiable {
    let id: UUID
    let code: String
    let hostId: UUID
    let hostUserId: UUID?
    var status: RoomStatus
    var numbers: [Int]?
    var round: Int

    enum CodingKeys: String, CodingKey {
        case id, code, status, numbers, round
        case hostId = "host_id"
        case hostUserId = "host_user_id"
    }
}

enum RoomStatus: String, Codable {
    case waiting, playing, finished
}

struct PlayerRow: Identifiable {
    let id: UUID
    let roomId: UUID
    let displayName: String
    var score: Int
    let isHost: Bool
    var readyRound: Int
}

extension PlayerRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id, score
        case roomId = "room_id"
        case displayName = "display_name"
        case isHost = "is_host"
        case readyRound = "ready_round"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roomId = try c.decode(UUID.self, forKey: .roomId)
        displayName = try c.decode(String.self, forKey: .displayName)
        score = try c.decode(Int.self, forKey: .score)
        isHost = try c.decode(Bool.self, forKey: .isHost)
        readyRound = (try? c.decode(Int.self, forKey: .readyRound)) ?? 0
    }
}

struct SubmissionRow: Codable, Identifiable {
    let id: UUID
    let roomId: UUID
    let playerId: UUID
    let round: Int
    let solution: String

    enum CodingKeys: String, CodingKey {
        case id, round, solution
        case roomId = "room_id"
        case playerId = "player_id"
    }
}

// MARK: - Social Models

struct ProfileRow: Codable, Identifiable {
    let id: UUID
    let username: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Daily Puzzle Models

struct DailyPuzzleState: Codable {
    let puzzleDate: String
    let numbers: [Int]
    let startedAt: Date?
    let completedMilliseconds: Int?

    enum CodingKeys: String, CodingKey {
        case numbers
        case puzzleDate = "puzzle_date"
        case startedAt = "started_at"
        case completedMilliseconds = "completed_milliseconds"
    }
}

struct DailyLeaderboardEntry: Codable, Identifiable {
    let rank: Int
    let userId: UUID
    let username: String
    let completedMilliseconds: Int
    let isCurrentUser: Bool

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case rank, username
        case userId = "user_id"
        case completedMilliseconds = "completed_milliseconds"
        case isCurrentUser = "is_current_user"
    }
}

struct SchoolDailyLeaderboardEntry: Codable, Identifiable {
    let rank: Int
    let schoolKey: String
    let averageMilliseconds: Int
    let solverCount: Int
    let isCurrentSchool: Bool

    var id: String { schoolKey }

    enum CodingKeys: String, CodingKey {
        case rank
        case schoolKey = "school_key"
        case averageMilliseconds = "average_milliseconds"
        case solverCount = "solver_count"
        case isCurrentSchool = "is_current_school"
    }
}

struct UniversityStatus: Codable {
    let email: String?
    let schoolKey: String
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case email
        case schoolKey = "school_key"
        case isVerified = "is_verified"
    }
}

struct FriendConnectionRow: Codable, Identifiable {
    let requestId: UUID
    let userId: UUID
    let username: String
    let status: String
    let direction: String
    let createdAt: Date

    var id: UUID { requestId }
    var isIncoming: Bool { direction == "incoming" }

    enum CodingKeys: String, CodingKey {
        case username, status, direction
        case requestId = "request_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct FriendSearchResult: Codable, Identifiable {
    let userId: UUID
    let username: String
    let mutualFriendCount: Int
    var relationshipState: String

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case username
        case userId = "user_id"
        case mutualFriendCount = "mutual_friend_count"
        case relationshipState = "relationship_state"
    }
}

// MARK: - Insert Payloads

struct RoomInsert: Sendable {
    let code: String
    let hostId: String
    let hostUserId: UUID
}

extension RoomInsert: Encodable {
    enum CodingKeys: String, CodingKey {
        case code
        case hostId = "host_id"
        case hostUserId = "host_user_id"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(hostId, forKey: .hostId)
        try c.encode(hostUserId, forKey: .hostUserId)
    }
}

struct PlayerInsert: Sendable {
    let id: String
    let roomId: String
    let displayName: String
    let isHost: Bool
}

extension PlayerInsert: Encodable {
    enum CodingKeys: String, CodingKey {
        case id
        case roomId = "room_id"
        case displayName = "display_name"
        case isHost = "is_host"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(roomId, forKey: .roomId)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(isHost, forKey: .isHost)
    }
}

// MARK: - RPC Params
// Explicit nonisolated encode(to:) prevents Swift 6 from inferring @MainActor
// on these synthesized Encodable conformances.

struct ClaimWinParams: Sendable {
    let pRoomId: UUID
    let pPlayerId: UUID
    let pRound: Int
    let pSolution: String
}

extension ClaimWinParams: Encodable {
    enum CodingKeys: String, CodingKey {
        case pRoomId = "p_room_id"
        case pPlayerId = "p_player_id"
        case pRound = "p_round"
        case pSolution = "p_solution"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pRoomId, forKey: .pRoomId)
        try c.encode(pPlayerId, forKey: .pPlayerId)
        try c.encode(pRound, forKey: .pRound)
        try c.encode(pSolution, forKey: .pSolution)
    }
}

struct StartRoundParams: Sendable {
    let pRoomId: UUID
    let pHostPlayerId: UUID
    let pNumbers: [Int]
}

extension StartRoundParams: Encodable {
    enum CodingKeys: String, CodingKey {
        case pRoomId = "p_room_id"
        case pHostPlayerId = "p_host_player_id"
        case pNumbers = "p_numbers"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pRoomId, forKey: .pRoomId)
        try c.encode(pHostPlayerId, forKey: .pHostPlayerId)
        try c.encode(pNumbers, forKey: .pNumbers)
    }
}

struct DissolveRoomParams: Sendable {
    let pRoomId: UUID
    let pHostId: UUID
}

struct UsernameParams: Sendable {
    let username: String
}

extension UsernameParams: Encodable {
    enum CodingKeys: String, CodingKey { case username = "p_username" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(username, forKey: .username)
    }
}

struct SearchProfilesParams: Sendable {
    let query: String
}

extension SearchProfilesParams: Encodable {
    enum CodingKeys: String, CodingKey { case query = "p_query" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .query)
    }
}

struct FriendUserParams: Sendable {
    let userId: UUID
}

extension FriendUserParams: Encodable {
    enum CodingKeys: String, CodingKey { case userId = "p_user_id" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
    }
}

struct FriendRequestParams: Sendable {
    let receiverId: UUID
}

extension FriendRequestParams: Encodable {
    enum CodingKeys: String, CodingKey { case receiverId = "p_receiver_id" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(receiverId, forKey: .receiverId)
    }
}

struct FriendResponseParams: Sendable {
    let requestId: UUID
    let accept: Bool
}

struct SubmitDailyPuzzleParams: Sendable {
    let puzzleDate: String
}

extension SubmitDailyPuzzleParams: Encodable {
    enum CodingKeys: String, CodingKey { case puzzleDate = "p_puzzle_date" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(puzzleDate, forKey: .puzzleDate)
    }
}

struct DailyLeaderboardParams: Sendable {
    let puzzleDate: String?
}

extension DailyLeaderboardParams: Encodable {
    enum CodingKeys: String, CodingKey { case puzzleDate = "p_puzzle_date" }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(puzzleDate, forKey: .puzzleDate)
    }
}

extension FriendResponseParams: Encodable {
    enum CodingKeys: String, CodingKey {
        case requestId = "p_request_id"
        case accept = "p_accept"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(accept, forKey: .accept)
    }
}

struct FriendNotificationBody: Sendable {
    let requestId: UUID
    let kind: String
}

struct RoomInviteNotificationBody: Sendable {
    let recipientId: UUID
    let roomCode: String
}

struct RegisterDeviceTokenParams: Sendable {
    let token: String
    let environment: String
}

extension RegisterDeviceTokenParams: Encodable {
    enum CodingKeys: String, CodingKey {
        case token = "p_token"
        case environment = "p_environment"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(environment, forKey: .environment)
    }
}

extension FriendNotificationBody: Encodable {
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case kind
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(kind, forKey: .kind)
    }
}

extension RoomInviteNotificationBody: Encodable {
    enum CodingKeys: String, CodingKey {
        case recipientId = "recipient_id"
        case roomCode = "room_code"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(recipientId, forKey: .recipientId)
        try c.encode(roomCode, forKey: .roomCode)
    }
}

extension DissolveRoomParams: Encodable {
    enum CodingKeys: String, CodingKey {
        case pRoomId = "p_room_id"
        case pHostId = "p_host_id"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pRoomId, forKey: .pRoomId)
        try c.encode(pHostId, forKey: .pHostId)
    }
}
