import SwiftUI
import Combine

// MARK: - Color Palette

struct ColorPalette {
    let name: String
    let icon: String

    // Backgrounds
    let backgroundTop: Color
    let backgroundBottom: Color
    let cardSurface: Color
    let surfaceOverlay: Color

    // Primary palette
    let brown: Color
    let amber: Color
    let cream: Color
    let warmGreen: Color
    let softOrange: Color

    // Card colors
    let cardColors: [Color]

    // Selected card
    let cardSelected: Color
    let cardSelectedText: Color

    // Operator bar
    let operatorBg: Color
    let operatorSelected: Color

    // Buttons
    let buttonPrimary: Color
    let buttonSecondary: Color

    // Scoreboard
    let scoreMe: Color
    let scoreOther: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
}

// MARK: - Built-in Palettes

extension ColorPalette {
    static let nature = ColorPalette(
        name: "Nature",
        icon: "leaf.fill",
        backgroundTop: .white,
        backgroundBottom: .white,
        cardSurface: .white,
        surfaceOverlay: Color.white.opacity(0.85),
        brown: Color(red: 0.35, green: 0.25, blue: 0.18),
        amber: Color(red: 0.82, green: 0.62, blue: 0.32),
        cream: Color(red: 0.96, green: 0.93, blue: 0.87),
        warmGreen: Color(red: 0.55, green: 0.68, blue: 0.48),
        softOrange: Color(red: 0.90, green: 0.72, blue: 0.50),
        cardColors: [
            Color(red: 0.93, green: 0.85, blue: 0.70),
            Color(red: 0.80, green: 0.87, blue: 0.73),
            Color(red: 0.90, green: 0.78, blue: 0.65),
            Color(red: 0.85, green: 0.82, blue: 0.75),
        ],
        cardSelected: Color(red: 0.42, green: 0.32, blue: 0.22),
        cardSelectedText: Color(red: 0.96, green: 0.93, blue: 0.87),
        operatorBg: Color(red: 0.93, green: 0.89, blue: 0.82),
        operatorSelected: Color(red: 0.42, green: 0.32, blue: 0.22),
        buttonPrimary: Color(red: 0.42, green: 0.32, blue: 0.22),
        buttonSecondary: Color(red: 0.93, green: 0.89, blue: 0.82),
        scoreMe: Color(red: 0.55, green: 0.68, blue: 0.48),
        scoreOther: Color(red: 0.93, green: 0.89, blue: 0.82),
        textPrimary: Color(red: 0.35, green: 0.25, blue: 0.18),
        textSecondary: Color(red: 0.35, green: 0.25, blue: 0.18).opacity(0.5),
        textMuted: Color(red: 0.35, green: 0.25, blue: 0.18).opacity(0.35)
    )

    static let ocean = ColorPalette(
        name: "Ocean",
        icon: "water.waves",
        backgroundTop: Color(red: 0.95, green: 0.97, blue: 1.0),
        backgroundBottom: Color(red: 0.95, green: 0.97, blue: 1.0),
        cardSurface: Color(red: 0.95, green: 0.97, blue: 1.0),
        surfaceOverlay: Color(red: 0.95, green: 0.97, blue: 1.0).opacity(0.85),
        brown: Color(red: 0.15, green: 0.25, blue: 0.40),
        amber: Color(red: 0.30, green: 0.60, blue: 0.78),
        cream: Color(red: 0.90, green: 0.94, blue: 0.98),
        warmGreen: Color(red: 0.30, green: 0.70, blue: 0.65),
        softOrange: Color(red: 0.55, green: 0.75, blue: 0.90),
        cardColors: [
            Color(red: 0.78, green: 0.88, blue: 0.96),
            Color(red: 0.72, green: 0.90, blue: 0.88),
            Color(red: 0.82, green: 0.85, blue: 0.95),
            Color(red: 0.75, green: 0.92, blue: 0.94),
        ],
        cardSelected: Color(red: 0.15, green: 0.35, blue: 0.55),
        cardSelectedText: Color(red: 0.92, green: 0.96, blue: 1.0),
        operatorBg: Color(red: 0.88, green: 0.93, blue: 0.98),
        operatorSelected: Color(red: 0.15, green: 0.35, blue: 0.55),
        buttonPrimary: Color(red: 0.15, green: 0.35, blue: 0.55),
        buttonSecondary: Color(red: 0.88, green: 0.93, blue: 0.98),
        scoreMe: Color(red: 0.30, green: 0.70, blue: 0.65),
        scoreOther: Color(red: 0.88, green: 0.93, blue: 0.98),
        textPrimary: Color(red: 0.15, green: 0.25, blue: 0.40),
        textSecondary: Color(red: 0.15, green: 0.25, blue: 0.40).opacity(0.5),
        textMuted: Color(red: 0.15, green: 0.25, blue: 0.40).opacity(0.35)
    )

    static let berry = ColorPalette(
        name: "Berry",
        icon: "circle.hexagongrid.fill",
        backgroundTop: Color(red: 0.98, green: 0.95, blue: 0.97),
        backgroundBottom: Color(red: 0.98, green: 0.95, blue: 0.97),
        cardSurface: Color(red: 0.98, green: 0.95, blue: 0.97),
        surfaceOverlay: Color(red: 0.98, green: 0.95, blue: 0.97).opacity(0.85),
        brown: Color(red: 0.35, green: 0.15, blue: 0.30),
        amber: Color(red: 0.75, green: 0.35, blue: 0.55),
        cream: Color(red: 0.96, green: 0.90, blue: 0.94),
        warmGreen: Color(red: 0.65, green: 0.40, blue: 0.70),
        softOrange: Color(red: 0.85, green: 0.55, blue: 0.65),
        cardColors: [
            Color(red: 0.92, green: 0.80, blue: 0.88),
            Color(red: 0.85, green: 0.78, blue: 0.92),
            Color(red: 0.95, green: 0.82, blue: 0.82),
            Color(red: 0.88, green: 0.82, blue: 0.90),
        ],
        cardSelected: Color(red: 0.45, green: 0.18, blue: 0.38),
        cardSelectedText: Color(red: 0.96, green: 0.92, blue: 0.95),
        operatorBg: Color(red: 0.94, green: 0.88, blue: 0.92),
        operatorSelected: Color(red: 0.45, green: 0.18, blue: 0.38),
        buttonPrimary: Color(red: 0.45, green: 0.18, blue: 0.38),
        buttonSecondary: Color(red: 0.94, green: 0.88, blue: 0.92),
        scoreMe: Color(red: 0.65, green: 0.40, blue: 0.70),
        scoreOther: Color(red: 0.94, green: 0.88, blue: 0.92),
        textPrimary: Color(red: 0.35, green: 0.15, blue: 0.30),
        textSecondary: Color(red: 0.35, green: 0.15, blue: 0.30).opacity(0.5),
        textMuted: Color(red: 0.35, green: 0.15, blue: 0.30).opacity(0.35)
    )

    static let midnight = ColorPalette(
        name: "Midnight",
        icon: "moon.stars.fill",
        backgroundTop: Color(red: 0.10, green: 0.10, blue: 0.14),
        backgroundBottom: Color(red: 0.10, green: 0.10, blue: 0.14),
        cardSurface: Color(red: 0.10, green: 0.10, blue: 0.14),
        surfaceOverlay: Color(red: 0.10, green: 0.10, blue: 0.14).opacity(0.85),
        brown: Color(red: 0.90, green: 0.88, blue: 0.82),
        amber: Color(red: 0.90, green: 0.72, blue: 0.35),
        cream: Color(red: 0.18, green: 0.18, blue: 0.22),
        warmGreen: Color(red: 0.45, green: 0.75, blue: 0.55),
        softOrange: Color(red: 0.85, green: 0.65, blue: 0.40),
        cardColors: [
            Color(red: 0.22, green: 0.22, blue: 0.28),
            Color(red: 0.20, green: 0.24, blue: 0.22),
            Color(red: 0.25, green: 0.22, blue: 0.20),
            Color(red: 0.20, green: 0.20, blue: 0.25),
        ],
        cardSelected: Color(red: 0.90, green: 0.72, blue: 0.35),
        cardSelectedText: Color(red: 0.10, green: 0.10, blue: 0.14),
        operatorBg: Color(red: 0.18, green: 0.18, blue: 0.22),
        operatorSelected: Color(red: 0.90, green: 0.72, blue: 0.35),
        buttonPrimary: Color(red: 0.90, green: 0.72, blue: 0.35),
        buttonSecondary: Color(red: 0.18, green: 0.18, blue: 0.22),
        scoreMe: Color(red: 0.45, green: 0.75, blue: 0.55),
        scoreOther: Color(red: 0.18, green: 0.18, blue: 0.22),
        textPrimary: Color(red: 0.90, green: 0.88, blue: 0.82),
        textSecondary: Color(red: 0.90, green: 0.88, blue: 0.82).opacity(0.5),
        textMuted: Color(red: 0.90, green: 0.88, blue: 0.82).opacity(0.35)
    )

    static let sunset = ColorPalette(
        name: "Sunset",
        icon: "sun.horizon.fill",
        backgroundTop: Color(red: 1.0, green: 0.97, blue: 0.94),
        backgroundBottom: Color(red: 1.0, green: 0.97, blue: 0.94),
        cardSurface: Color(red: 1.0, green: 0.97, blue: 0.94),
        surfaceOverlay: Color(red: 1.0, green: 0.97, blue: 0.94).opacity(0.85),
        brown: Color(red: 0.40, green: 0.18, blue: 0.12),
        amber: Color(red: 0.92, green: 0.50, blue: 0.25),
        cream: Color(red: 0.98, green: 0.92, blue: 0.86),
        warmGreen: Color(red: 0.85, green: 0.55, blue: 0.30),
        softOrange: Color(red: 0.95, green: 0.65, blue: 0.40),
        cardColors: [
            Color(red: 0.98, green: 0.85, blue: 0.72),
            Color(red: 0.95, green: 0.78, blue: 0.68),
            Color(red: 0.98, green: 0.82, blue: 0.75),
            Color(red: 0.92, green: 0.80, blue: 0.72),
        ],
        cardSelected: Color(red: 0.50, green: 0.20, blue: 0.12),
        cardSelectedText: Color(red: 1.0, green: 0.95, blue: 0.90),
        operatorBg: Color(red: 0.96, green: 0.90, blue: 0.84),
        operatorSelected: Color(red: 0.50, green: 0.20, blue: 0.12),
        buttonPrimary: Color(red: 0.50, green: 0.20, blue: 0.12),
        buttonSecondary: Color(red: 0.96, green: 0.90, blue: 0.84),
        scoreMe: Color(red: 0.85, green: 0.55, blue: 0.30),
        scoreOther: Color(red: 0.96, green: 0.90, blue: 0.84),
        textPrimary: Color(red: 0.40, green: 0.18, blue: 0.12),
        textSecondary: Color(red: 0.40, green: 0.18, blue: 0.12).opacity(0.5),
        textMuted: Color(red: 0.40, green: 0.18, blue: 0.12).opacity(0.35)
    )

    static let all: [ColorPalette] = [.nature, .ocean, .berry, .midnight, .sunset]
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var current: ColorPalette {
        didSet {
            UserDefaults.standard.set(current.name, forKey: "selectedTheme")
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "selectedTheme") ?? "Nature"
        current = ColorPalette.all.first { $0.name == saved } ?? .nature
    }
}

// MARK: - Theme (static access)

enum Theme {
    private static var p: ColorPalette { ThemeManager.shared.current }

    // Backgrounds
    static var backgroundTop: Color { p.backgroundTop }
    static var backgroundBottom: Color { p.backgroundBottom }
    static var cardSurface: Color { p.cardSurface }
    static var surfaceOverlay: Color { p.surfaceOverlay }

    // Primary palette
    static var brown: Color { p.brown }
    static var amber: Color { p.amber }
    static var cream: Color { p.cream }
    static var warmGreen: Color { p.warmGreen }
    static var softOrange: Color { p.softOrange }

    // Card colors
    static var cardColors: [Color] { p.cardColors }

    // Selected card
    static var cardSelected: Color { p.cardSelected }
    static var cardSelectedText: Color { p.cardSelectedText }

    // Operator bar
    static var operatorBg: Color { p.operatorBg }
    static var operatorSelected: Color { p.operatorSelected }

    // Buttons
    static var buttonPrimary: Color { p.buttonPrimary }
    static var buttonSecondary: Color { p.buttonSecondary }

    // Scoreboard
    static var scoreMe: Color { p.scoreMe }
    static var scoreOther: Color { p.scoreOther }

    // Text
    static var textPrimary: Color { p.textPrimary }
    static var textSecondary: Color { p.textSecondary }
    static var textMuted: Color { p.textMuted }

    // Background gradient
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
