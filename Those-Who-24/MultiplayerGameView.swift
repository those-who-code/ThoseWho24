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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.cream.opacity(0.7))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Round \(vm.currentRoom?.round ?? 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Theme.cream.opacity(0.7))
                    .clipShape(Capsule())

                Spacer()

                Color.clear.frame(width: 32, height: 32)
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
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
                .padding(.bottom, 32)

            // Cards 2x2
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(Array(gameVM.cards.enumerated()), id: \.element.id) { index, card in
                    MinimalCardView(
                        fraction: card.value,
                        isSelected: gameVM.selectedCardIndex == index,
                        isVisible: card.isVisible,
                        colorIndex: index
                    )
                    .onTapGesture {
                        Haptics.selection()
                        gameVM.handleCardTap(at: index)
                    }
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            if !gameVM.didWin {
                // Operators
                HStack(spacing: 4) {
                    ForEach(MathOperator.allCases, id: \.self) { op in
                        Button {
                            Haptics.light()
                            gameVM.selectedOperator = op
                        } label: {
                            Text(op.rawValue)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundColor(gameVM.selectedOperator == op ? Theme.cardSelectedText : Theme.brown)
                                .background(
                                    gameVM.selectedOperator == op ? Theme.operatorSelected : Theme.operatorBg
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Theme.cream.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 32)

                // Bottom buttons
                HStack(spacing: 12) {
                    BottomButton(label: "Undo", icon: "arrow.uturn.backward", enabled: gameVM.canUndo) {
                        Haptics.medium()
                        gameVM.undo()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .onChange(of: gameVM.didWin) { _, won in
            if won {
                Task { await vm.submitSolution() }
            }
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
                        .foregroundColor(isMe ? Theme.accentText : Theme.brown)
                    Text(player.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(
                            isMe ? Theme.accentText.opacity(0.85) : Theme.textSecondary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isMe ? Theme.scoreMe : Theme.scoreOther)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
