import SwiftUI

// MARK: - Fun Nature Theme

enum Theme {
    // Backgrounds
    static let backgroundTop = Color.white
    static let backgroundBottom = Color.white
    static let cardSurface = Color.white
    static let surfaceOverlay = Color.white.opacity(0.85)

    // Primary palette
    static let brown = Color(red: 0.35, green: 0.25, blue: 0.18)            // Dark brown text
    static let amber = Color(red: 0.82, green: 0.62, blue: 0.32)            // Warm amber accent
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.87)            // Cream
    static let warmGreen = Color(red: 0.55, green: 0.68, blue: 0.48)        // Nature green
    static let softOrange = Color(red: 0.90, green: 0.72, blue: 0.50)       // Soft orange

    // Card colors (earthy, playful)
    static let cardColors: [Color] = [
        Color(red: 0.93, green: 0.85, blue: 0.70),  // Warm sand
        Color(red: 0.80, green: 0.87, blue: 0.73),  // Soft green
        Color(red: 0.90, green: 0.78, blue: 0.65),  // Peach
        Color(red: 0.85, green: 0.82, blue: 0.75),  // Warm gray
    ]

    // Selected card
    static let cardSelected = Color(red: 0.42, green: 0.32, blue: 0.22)     // Rich brown
    static let cardSelectedText = Color(red: 0.96, green: 0.93, blue: 0.87)

    // Operator bar
    static let operatorBg = Color(red: 0.93, green: 0.89, blue: 0.82)
    static let operatorSelected = Color(red: 0.42, green: 0.32, blue: 0.22)

    // Buttons
    static let buttonPrimary = Color(red: 0.42, green: 0.32, blue: 0.22)
    static let buttonSecondary = Color(red: 0.93, green: 0.89, blue: 0.82)

    // Scoreboard
    static let scoreMe = Color(red: 0.55, green: 0.68, blue: 0.48)
    static let scoreOther = Color(red: 0.93, green: 0.89, blue: 0.82)

    // Text
    static let textPrimary = Color(red: 0.35, green: 0.25, blue: 0.18)
    static let textSecondary = Color(red: 0.35, green: 0.25, blue: 0.18).opacity(0.5)
    static let textMuted = Color(red: 0.35, green: 0.25, blue: 0.18).opacity(0.35)

    // Background gradient
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
