import SwiftUI

private enum FriendsTab: String, CaseIterable {
    case friends = "Friends"
    case requests = "Requests"
}

struct FriendsView: View {
    @Bindable var manager: FriendsManager
    var initiallyShowsRequests = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: FriendsTab = .friends
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                searchField

                if !searchText.isEmpty {
                    searchContent
                } else {
                    tabPicker
                    connectionContent
                }
            }
        }
        .task {
            if initiallyShowsRequests {
                selectedTab = .requests
            }
            await manager.refreshConnections()
        }
        .task(id: searchText) {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                await manager.search(searchText)
            } catch {}
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { manager.errorMessage != nil },
                set: { if !$0 { manager.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { manager.errorMessage = nil }
        } message: {
            Text(manager.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Friends")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                if let username = manager.username {
                    Text("@\(username)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Theme.cream)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Theme.textMuted)
            TextField("Search by username", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Theme.brown)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 16, weight: .medium, design: .rounded))
        .padding(.horizontal, 15)
        .frame(height: 50)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(FriendsTab.allCases, id: \.self) { tab in
                Button {
                    Haptics.selection()
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Text(tab.rawValue)
                        if tab == .requests && manager.pendingRequestCount > 0 {
                            Text("\(manager.pendingRequestCount)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Theme.accentText)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Theme.amber)
                                .clipShape(Circle())
                        }
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(
                        selectedTab == tab ? Theme.cardSelectedText : Theme.textSecondary
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        selectedTab == tab ? Theme.buttonPrimary : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var connectionContent: some View {
        switch selectedTab {
        case .friends:
            if manager.friends.isEmpty {
                emptyState(
                    icon: "person.2",
                    title: "No friends yet",
                    message: "Search for a username to connect."
                )
            } else {
                connectionList(manager.friends)
            }
        case .requests:
            let requests = manager.incomingRequests + manager.outgoingRequests
            if requests.isEmpty {
                emptyState(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "You're all caught up",
                    message: "New friend requests will appear here."
                )
            } else {
                connectionList(requests)
            }
        }
    }

    private var searchContent: some View {
        Group {
            if searchText.count < 2 {
                emptyState(
                    icon: "text.magnifyingglass",
                    title: "Type at least 2 characters",
                    message: "Search uses the beginning of a username."
                )
            } else if manager.isSearching {
                Spacer()
                ProgressView().tint(Theme.amber)
                Spacer()
            } else if manager.searchResults.isEmpty {
                emptyState(
                    icon: "person.slash",
                    title: "No usernames found",
                    message: "Check the spelling and try again."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(manager.searchResults) { result in
                            SearchResultRow(result: result) {
                                Task { await manager.sendRequest(to: result) }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private func connectionList(_ rows: [FriendConnectionRow]) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(rows) { connection in
                    FriendConnectionCard(
                        connection: connection,
                        onAccept: {
                            Task { await manager.respond(to: connection, accept: true) }
                        },
                        onReject: {
                            Task { await manager.respond(to: connection, accept: false) }
                        },
                        onRemove: {
                            Task { await manager.remove(connection) }
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundColor(Theme.amber.opacity(0.75))
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brown)
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

private struct SearchResultRow: View {
    let result: FriendSearchResult
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar(result.username)
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(result.username)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                Text(mutualText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            relationshipButton
        }
        .padding(14)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var mutualText: String {
        switch result.mutualFriendCount {
        case 0: return "No mutual friends"
        case 1: return "1 mutual friend"
        default: return "\(result.mutualFriendCount) mutual friends"
        }
    }

    @ViewBuilder
    private var relationshipButton: some View {
        switch result.relationshipState {
        case "friends":
            Label("Friends", systemImage: "checkmark")
                .foregroundColor(Theme.textPrimary)
        case "outgoing":
            Text("Requested")
                .foregroundColor(Theme.textSecondary)
        case "incoming":
            Text("Respond in Requests")
                .foregroundColor(Theme.textPrimary)
        default:
            Button(action: onAdd) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Theme.cardSelectedText)
                    .frame(width: 38, height: 34)
                    .background(Theme.buttonPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct FriendConnectionCard: View {
    let connection: FriendConnectionRow
    let onAccept: () -> Void
    let onReject: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            avatar(connection.username)
            VStack(alignment: .leading, spacing: 3) {
                Text("@\(connection.username)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.brown)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            actions
        }
        .padding(14)
        .background(Theme.cream)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var subtitle: String {
        if connection.status == "accepted" { return "Friend" }
        return connection.isIncoming ? "Wants to be friends" : "Request sent"
    }

    @ViewBuilder
    private var actions: some View {
        if connection.status == "pending" && connection.isIncoming {
            HStack(spacing: 7) {
                Button(action: onReject) {
                    Image(systemName: "xmark")
                        .frame(width: 34, height: 34)
                        .background(Theme.cardSurface)
                        .clipShape(Circle())
                }
                Button(action: onAccept) {
                    Image(systemName: "checkmark")
                        .foregroundColor(Theme.cardSelectedText)
                        .frame(width: 34, height: 34)
                        .background(Theme.buttonPrimary)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
        } else {
            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label(
                        connection.status == "accepted" ? "Remove Friend" : "Cancel Request",
                        systemImage: "trash"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
    }
}

private func avatar(_ username: String) -> some View {
    Text(String(username.prefix(1)).uppercased())
        .font(.system(size: 17, weight: .bold, design: .rounded))
        .foregroundColor(Theme.accentText)
        .frame(width: 42, height: 42)
        .background(Theme.amber)
        .clipShape(Circle())
}
