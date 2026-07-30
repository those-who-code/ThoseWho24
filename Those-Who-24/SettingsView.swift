import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    let onBack: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var stats = StatsManager.shared
    @State private var friends = FriendsManager.shared
    @State private var showResetAlert = false
    @State private var showFriends = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Haptics.light()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Back")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 24) {
                        profileSection

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color Theme")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.textSecondary)

                            ForEach(ColorPalette.all, id: \.name) { palette in
                                ThemeRow(
                                    palette: palette,
                                    isSelected: themeManager.current.name == palette.name
                                ) {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        themeManager.current = palette
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        if stats.lifetimeSolves > 0 {
                            Button {
                                Haptics.light()
                                showResetAlert = true
                            } label: {
                                Text("Reset all stats")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(Theme.destructiveText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.cream)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 24)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showFriends) {
            FriendsView(manager: friends)
        }
        .task {
            await friends.refreshConnections()
        }
        .alert("Reset all stats?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) { stats.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(stats.lifetimeSolves) solve records.")
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.textSecondary)

            VStack(spacing: 14) {
                HStack(spacing: 13) {
                    Text(String((friends.username ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.accentText)
                        .frame(width: 52, height: 52)
                        .background(Theme.amber)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("@\(friends.username ?? "username")")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundColor(Theme.brown)
                        Text("\(friends.friends.count) friend\(friends.friends.count == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    if friends.pendingRequestCount > 0 {
                        Text("\(friends.pendingRequestCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Theme.accentText)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Theme.amber)
                            .clipShape(Circle())
                    }
                }

                if !friends.friends.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(friends.friends.prefix(3).enumerated()), id: \.element.id) { index, friend in
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.amber)
                                Text("@\(friend.username)")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(Theme.brown)
                                Spacer()
                            }
                            .padding(.vertical, 9)

                            if index < min(friends.friends.count, 3) - 1 {
                                Divider().opacity(0.35)
                            }
                        }
                    }
                }

                Button {
                    Haptics.light()
                    showFriends = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "person.badge.plus")
                        Text(friends.friends.isEmpty ? "Add Friends" : "Manage Friends")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.cardSelectedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.buttonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Theme.cream)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Theme Row

private struct ThemeRow: View {
    let palette: ColorPalette
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: palette.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(palette.amber)
                    .frame(width: 36, height: 36)
                    .background(palette.cream)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(palette.name)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.brown)

                    HStack(spacing: 4) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(palette.cardColors[i])
                                .frame(width: 14, height: 14)
                        }
                        Circle()
                            .fill(palette.cardSelected)
                            .frame(width: 14, height: 14)
                        Circle()
                            .fill(palette.amber)
                            .frame(width: 14, height: 14)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Theme.amber)
                }
            }
            .padding(16)
            .background(isSelected ? Theme.cream : Theme.cream.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Theme.amber.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
