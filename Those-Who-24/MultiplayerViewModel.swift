import SwiftUI

// MARK: - Lobby State

enum LobbyState: Equatable {
    case nameEntry
    case loading
    case waitingRoom
    case playing
    case roundOver(winnerName: String, didWin: Bool, winnerSolution: String)
    case dissolved(reason: String)

    static func == (lhs: LobbyState, rhs: LobbyState) -> Bool {
        switch (lhs, rhs) {
        case (.nameEntry, .nameEntry),
             (.loading, .loading),
             (.waitingRoom, .waitingRoom),
             (.playing, .playing):
            return true
        case (.roundOver(let a, let b, let c), .roundOver(let d, let e, let f)):
            return a == d && b == e && c == f
        case (.dissolved(let a), .dissolved(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - MultiplayerViewModel

@Observable
@MainActor
class MultiplayerViewModel {
    var state: LobbyState = .nameEntry
    var displayName: String = ""
    var joinCode: String = ""
    var errorMessage: String? = nil
    var players: [PlayerRow] = []
    var currentRoom: RoomRow? = nil
    var gameVM: GameViewModel? = nil
    private(set) var invitedFriendIds: Set<UUID> = []
    private(set) var invitingFriendIds: Set<UUID> = []

    private(set) var myPlayerId: UUID? = nil
    private(set) var myRoomId: UUID? = nil
    private(set) var isHost: Bool = false

    private let service = SupabaseService.shared
    private var subscriptionTask: Task<Void, Never>? = nil
    private var heartbeatTask: Task<Void, Never>? = nil

    // MARK: - Lobby Actions

    func createRoom() async {
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a display name first."
            return
        }
        state = .loading
        errorMessage = nil
        do {
            let (room, player) = try await service.createRoom(displayName: displayName)
            myPlayerId = player.id
            myRoomId = room.id
            isHost = true
            currentRoom = room
            players = [player]
            beginSubscriptions(roomId: room.id)
            startHeartbeat(playerId: player.id)
            state = .waitingRoom
        } catch {
            errorMessage = error.localizedDescription
            state = .nameEntry
        }
    }

    func joinRoom() async {
        let code = joinCode.trimmingCharacters(in: .whitespaces).uppercased()
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter a display name first."
            return
        }
        guard code.count == 6 else {
            errorMessage = "Enter a valid 6-character room code."
            return
        }
        state = .loading
        errorMessage = nil
        do {
            let (room, player) = try await service.joinRoom(code: code, displayName: displayName)
            myPlayerId = player.id
            myRoomId = room.id
            isHost = false
            currentRoom = room
            players = try await service.fetchPlayers(roomId: room.id)
            beginSubscriptions(roomId: room.id)
            startHeartbeat(playerId: player.id)
            state = .waitingRoom
        } catch {
            errorMessage = error.localizedDescription
            state = .nameEntry
        }
    }

    func startGame() async {
        guard isHost, let roomId = myRoomId, let playerId = myPlayerId else { return }
        guard players.count >= 2 else { return }
        let numbers = generateSolvablePuzzle()
        do {
            try await service.startRound(roomId: roomId, hostPlayerId: playerId, numbers: numbers)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inviteFriend(_ friend: FriendConnectionRow) async {
        guard isHost, let roomCode = currentRoom?.code else { return }
        guard !invitedFriendIds.contains(friend.userId),
              !invitingFriendIds.contains(friend.userId) else { return }

        invitingFriendIds.insert(friend.userId)
        defer { invitingFriendIds.remove(friend.userId) }
        do {
            try await service.sendRoomInvite(
                to: friend.userId,
                roomCode: roomCode
            )
            invitedFriendIds.insert(friend.userId)
            Haptics.successDoubleTap()
        } catch {
            errorMessage = "Couldn’t invite @\(friend.username). \(error.localizedDescription)"
        }
    }

    func leaveRoom() async {
        subscriptionTask?.cancel()
        heartbeatTask?.cancel()
        if let playerId = myPlayerId, let roomId = myRoomId {
            try? await service.leaveRoom(playerId: playerId, roomId: roomId, isHost: isHost)
        }
        resetToNameEntry()
    }

    func submitSolution() async {
        guard let roomId = myRoomId,
              let playerId = myPlayerId,
              let room = currentRoom,
              let gvm = gameVM,
              gvm.didWin else { return }

        let moves = gvm.playerMoves
        let displayStr: String
        let indexStr: String
        if !moves.isEmpty {
            displayStr = moves.map { "\($0.aLabel) \($0.op) \($0.bLabel) = \($0.resultLabel)" }.joined(separator: ", ")
            indexStr = moves.map { "\($0.firstIdx):\($0.secondIdx):\($0.op):\($0.resultLabel)" }.joined(separator: ",")
        } else {
            displayStr = gvm.allSolutions.first.map { sol in
                sol.steps.map { "\($0.a) \($0.op) \($0.b) = \($0.result)" }.joined(separator: ", ")
            } ?? "solved"
            indexStr = ""
        }
        let solutionStr = indexStr.isEmpty ? displayStr : "\(displayStr)|\(indexStr)"

        do {
            let won = try await service.submitSolution(
                roomId: roomId, playerId: playerId,
                round: room.round, solution: solutionStr
            )
            if !won {
                Haptics.extendedError()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Realtime Subscriptions

    private func beginSubscriptions(roomId: UUID) {
        subscriptionTask?.cancel()
        subscriptionTask = service.subscribe(
            roomId: roomId,
            onRoomUpdate: { [weak self] room in
                Task { @MainActor [weak self] in
                    self?.handleRoomUpdate(room)
                }
            },
            onPlayersChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, let roomId = self.myRoomId else { return }
                    if let updated = try? await self.service.fetchPlayers(roomId: roomId) {
                        self.players = updated
                        // Host starts next round once every player has marked ready
                        if self.isHost, case .roundOver = self.state {
                            let currentRound = self.currentRoom?.round ?? 0
                            let allReady = !updated.isEmpty && updated.allSatisfy { $0.readyRound >= currentRound }
                            if allReady {
                                let numbers = self.generateSolvablePuzzle()
                                if let rId = self.myRoomId, let pId = self.myPlayerId {
                                    try? await self.service.startRound(roomId: rId, hostPlayerId: pId, numbers: numbers)
                                }
                            }
                        }
                    }
                }
            },
            onSubmission: { [weak self] submission in
                Task { @MainActor [weak self] in
                    self?.handleSubmission(submission)
                }
            }
        )
    }

    private func handleRoomUpdate(_ room: RoomRow) {
        currentRoom = room
        switch room.status {
        case .playing:
            guard let numbers = room.numbers, numbers.count == 4 else { return }
            dealRound(numbers: numbers)
        case .finished:
            subscriptionTask?.cancel()
            heartbeatTask?.cancel()
            state = .dissolved(reason: "The host ended the game.")
        case .waiting:
            break
        }
    }

    private func handleSubmission(_ submission: SubmissionRow) {
        guard let room = currentRoom, submission.round == room.round else { return }

        let winner = players.first { $0.id == submission.playerId }
        let winnerName = winner?.displayName ?? "Someone"
        let didIWin = submission.playerId == myPlayerId

        state = .roundOver(winnerName: winnerName, didWin: didIWin, winnerSolution: submission.solution)

        if let idx = players.firstIndex(where: { $0.id == submission.playerId }) {
            players[idx].score += 1
        }

    }

    func markReady() async {
        guard let playerId = myPlayerId, let round = currentRoom?.round,
              case .roundOver = state else { return }
        try? await service.markReady(playerId: playerId, round: round)
    }

    private func dealRound(numbers: [Int]) {
        let gvm = GameViewModel()
        gvm.setupMultiplayerRound(numbers: numbers)
        gameVM = gvm
        state = .playing
    }

    // MARK: - Puzzle Generation

    private func generateSolvablePuzzle() -> [Int] {
        var values: [Fraction]
        repeat {
            values = (0..<4).map { _ in Fraction(Int.random(in: 1...13)) }
        } while findAllSolutions(values: values).isEmpty
        return values.map { $0.num }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(playerId: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self?.service.pingPlayer(playerId: playerId)
            }
        }
    }

    // MARK: - Reset

    private func resetToNameEntry() {
        myPlayerId = nil
        myRoomId = nil
        isHost = false
        currentRoom = nil
        players = []
        gameVM = nil
        invitedFriendIds = []
        invitingFriendIds = []
        errorMessage = nil
        state = .nameEntry
    }

    func dismissError() {
        errorMessage = nil
        if case .dissolved = state {
            resetToNameEntry()
        }
    }
}
