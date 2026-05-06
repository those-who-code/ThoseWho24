import Foundation

// MARK: - DB Row Models

struct RoomRow: Codable, Identifiable {
    let id: UUID
    let code: String
    let hostId: UUID
    var status: RoomStatus
    var numbers: [Int]?
    var round: Int

    enum CodingKeys: String, CodingKey {
        case id, code, status, numbers, round
        case hostId = "host_id"
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

// MARK: - Insert Payloads

struct RoomInsert: Sendable {
    let code: String
    let hostId: String
}

extension RoomInsert: Encodable {
    enum CodingKeys: String, CodingKey {
        case code
        case hostId = "host_id"
    }
    nonisolated func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(hostId, forKey: .hostId)
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
