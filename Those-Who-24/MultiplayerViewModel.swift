import SwiftUI

// MARK: - Lobby State

enum LobbyState: Equatable {
    case nameEntry
    case loading
    case waitingRoom
    case playing
    case roundOver(winnerName: String, didWin: Bool)
    case dissolved(reason: String)

    static func == (lhs: LobbyState, rhs: LobbyState) -> Bool {
        switch (lhs, rhs) {
        case (.nameEntry, .nameEntry),
             (.loading, .loading),
             (.waitingRoom, .waitingRoom),
             (.playing, .playing):
            return true
        case (.roundOver(let a, let b), .roundOver(let c, let d)):
            return a == c && b == d
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

        let solutionStr = gvm.allSolutions.first.map { steps in
            steps.map { "\($0.a) \($0.op) \($0.b) = \($0.result)" }.joined(separator: ", ")
        } ?? "solved"

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

        state = .roundOver(winnerName: winnerName, didWin: didIWin)

        if let idx = players.firstIndex(where: { $0.id == submission.playerId }) {
            players[idx].score += 1
        }

        if isHost {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                guard let self, let roomId = self.myRoomId, let playerId = self.myPlayerId else { return }
                let numbers = self.generateSolvablePuzzle()
                try? await self.service.startRound(roomId: roomId, hostPlayerId: playerId, numbers: numbers)
            }
        }
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
