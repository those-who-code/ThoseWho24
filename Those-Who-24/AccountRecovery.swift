import SwiftUI

@Observable
@MainActor
final class RecoveryManager {
    static let shared = RecoveryManager()

    private(set) var myRequests: [RecoveryRequestRow] = []
    private(set) var adminRequests: [AdminRecoveryRequestRow] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let service = SupabaseService.shared
    private init() {}

    var activeRequest: RecoveryRequestRow? {
        myRequests.first { $0.status == "pending" || $0.status == "approved" }
    }

    func refreshMine() async {
        guard FriendsManager.shared.isAppleBacked else { return }
        do {
            myRequests = try await service.fetchMyRecoveryRequests()
        } catch {
            // Recovery status is supplementary and should not block the app.
        }
    }

    func submit(username: String, note: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let request = try await service.createRecoveryRequest(
                username: username.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                note: note
            )
            myRequests.insert(request, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func complete(_ request: RecoveryRequestRow) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await service.completeRecoveryRequest(id: request.id)
            await FriendsManager.shared.didCompleteRecovery(profile)
            await refreshMine()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAdmin() async {
        guard FriendsManager.shared.isAdmin else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            adminRequests = try await service.fetchAdminRecoveryRequests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func review(_ request: AdminRecoveryRequestRow, approve: Bool) async {
        errorMessage = nil
        do {
            try await service.reviewRecoveryRequest(id: request.id, approve: approve)
            await refreshAdmin()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RecoveryCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = RecoveryManager.shared
    @State private var username = ""
    @State private var note = ""
    @State private var showCompletionConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in with Apple first, then request restoration of a username you previously owned. Requests are reviewed in-app by the developer.")
                }

                if let request = manager.activeRequest {
                    Section("Request \(shortCaseId(request.id))") {
                        LabeledContent("Username", value: "@\(request.claimedUsername)")
                        LabeledContent("Status", value: request.status.capitalized)
                        if request.status == "pending" {
                            Text("Your request is awaiting review. Return here to see its status.")
                                .foregroundStyle(.secondary)
                        } else if request.status == "approved" {
                            Text("Recovery is approved. Confirming will restore the old username, friends, university, and saved daily completion dates to this Apple account.")
                                .foregroundStyle(.secondary)
                            Button("Review and restore account") {
                                showCompletionConfirmation = true
                            }
                        }
                    }
                } else {
                    Section("Lost account") {
                        TextField("Previous username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("What happened? (optional)", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                        Button(manager.isLoading ? "Submitting…" : "Submit recovery request") {
                            Task {
                                if await manager.submit(username: username, note: note) {
                                    username = ""
                                    note = ""
                                }
                            }
                        }
                        .disabled(manager.isLoading || username.count < 3)
                    }
                }

                if let error = manager.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Account Recovery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await manager.refreshMine() }
            .confirmationDialog(
                "Restore @\(manager.activeRequest?.claimedUsername ?? "account")?",
                isPresented: $showCompletionConfirmation,
                titleVisibility: .visible
            ) {
                if let request = manager.activeRequest {
                    Button("Restore account", role: .destructive) {
                        Task {
                            if await manager.complete(request) { dismiss() }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current replacement username will be released. Recoverable account data will be merged.")
            }
        }
    }

    private func shortCaseId(_ id: UUID) -> String {
        "R-" + id.uuidString.prefix(6).uppercased()
    }
}

struct RecoveryAdminView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var manager = RecoveryManager.shared

    var body: some View {
        NavigationStack {
            List {
                if manager.adminRequests.isEmpty, !manager.isLoading {
                    ContentUnavailableView("No recovery requests", systemImage: "person.crop.circle.badge.checkmark")
                }
                ForEach(manager.adminRequests) { request in
                    Section {
                        LabeledContent("Claimed account", value: "@\(request.claimedUsername)")
                        if let current = request.currentUsername {
                            LabeledContent("Current account", value: "@\(current)")
                        }
                        LabeledContent("Friends", value: "\(request.oldFriendCount)")
                        LabeledContent("Daily completions", value: "\(request.oldCompletionCount)")
                        if request.oldIsAppleBacked {
                            Label("Already protected by Apple — do not approve", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        if let note = request.note, !note.isEmpty { Text(note) }
                        LabeledContent("Status", value: request.status.capitalized)
                        if request.status == "pending" {
                            HStack {
                                Button("Reject", role: .destructive) {
                                    Task { await manager.review(request, approve: false) }
                                }
                                Spacer()
                                Button("Approve") {
                                    Task { await manager.review(request, approve: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(request.oldIsAppleBacked)
                            }
                        }
                    } header: {
                        Text("R-\(request.id.uuidString.prefix(6).uppercased())")
                    }
                }
            }
            .navigationTitle("Recovery Admin")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { Task { await manager.refreshAdmin() } }
                }
            }
            .task { await manager.refreshAdmin() }
        }
    }
}
