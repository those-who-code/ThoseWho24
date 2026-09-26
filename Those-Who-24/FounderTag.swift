import SwiftUI

enum FounderAccount {
    private static let usernames: Set<String> = [
        "priscillaye",
        "azxli",
        "allen",
        "nike276",
        "allu",
        "aus",
    ]

    static func isFounder(_ username: String) -> Bool {
        usernames.contains(normalized(username))
    }

    static func hasShinyTag(_ username: String) -> Bool {
        normalized(username) == "priscillaye"
    }

    static func isRepoContributor(_ username: String) -> Bool {
        normalized(username) == "allu"
    }

    private static func normalized(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct FounderTag: View {
    let username: String

    @ViewBuilder
    var body: some View {
        if FounderAccount.isFounder(username) || FounderAccount.isRepoContributor(username) {
            VStack(alignment: .leading, spacing: 3) {
                if FounderAccount.isFounder(username) {
                    founderBadge
                }

                if FounderAccount.isRepoContributor(username) {
                    Text("w repo contributor")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .tracking(0.15)
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Theme.warmGreen)
                        .clipShape(Capsule())
                        .fixedSize()
                        .accessibilityLabel("W repo contributor")
                }
            }
        }
    }

    private var founderBadge: some View {
        let isShiny = FounderAccount.hasShinyTag(username)

        return HStack(spacing: 3) {
            if isShiny {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
            }
            Text("FOUNDER")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(0.45)
        }
        .foregroundStyle(isShiny ? Theme.accentText : Theme.cardSelectedText)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background {
            if isShiny {
                LinearGradient(
                    colors: [Theme.amber, Theme.cardSelectedText, Theme.softOrange, Theme.amber],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Theme.buttonPrimary
            }
        }
        .overlay {
            if isShiny {
                Capsule()
                    .stroke(Theme.amber.opacity(0.9), lineWidth: 1)
            }
        }
        .clipShape(Capsule())
        .fixedSize()
        .accessibilityLabel(isShiny ? "Founder, shiny badge" : "Founder")
    }
}
