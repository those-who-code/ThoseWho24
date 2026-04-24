import SwiftUI

// MARK: - Multiplayer Game View

struct MultiplayerGameView: View {
    var vm: MultiplayerViewModel
    @ObservedObject var gameVM: GameViewModel
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: round + leave
            HStack {
                Button {
                    Haptics.medium()
                    Task { await vm.leaveRoom() }
                    onExit()
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black.opacity(0.35))
                }

                Spacer()

                Text("Round \(vm.currentRoom?.round ?? 1)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.5))

                Spacer()

                // Balance the layout
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Scoreboard
            ScoreboardView(players: vm.players, myPlayerId: vm.myPlayerId)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            Spacer()

            // Message
            Text(gameVM.message)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.black)
                .padding(.bottom, 32)

            // Cards 2x2
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(Array(gameVM.cards.enumerated()), id: \.element.id) { index, card in
                    MinimalCardView(
                        fraction: card.value,
                        isSelected: gameVM.selectedCardIndex == index,
                        isVisible: card.isVisible
                    )
                    .onTapGesture {
                        Haptics.selection()
                        gameVM.handleCardTap(at: index)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            // Operators
            HStack(spacing: 0) {
                ForEach(MathOperator.allCases, id: \.self) { op in
                    Button {
                        Haptics.light()
                        gameVM.selectedOperator = op
                    } label: {
                        Text(op.rawValue)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundColor(gameVM.selectedOperator == op ? .white : .black)
                            .background(
                                gameVM.selectedOperator == op ? Color.black : Color.clear
                            )
                    }
                }
            }
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 32)

            // Bottom buttons
            HStack(spacing: 12) {
                BottomButton(label: "Undo", icon: "arrow.uturn.backward", enabled: gameVM.canUndo) {
                    Haptics.medium()
                    gameVM.undo()
                }
                BottomButton(label: "Submit", icon: "checkmark", filled: true,
                             enabled: gameVM.didWin) {
                    Haptics.heavy()
                    Task { await vm.submitSolution() }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Scoreboard View

struct ScoreboardView: View {
    let players: [PlayerRow]
    let myPlayerId: UUID?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(players) { player in
                let isMe = player.id == myPlayerId
                VStack(spacing: 2) {
                    Text("\(player.score)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isMe ? .white : .black)
                    Text(player.displayName)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(isMe ? .white.opacity(0.75) : .black.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isMe ? Color.black : Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}
