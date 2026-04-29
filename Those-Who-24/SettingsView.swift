import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    let onBack: () -> Void
    @ObservedObject private var themeManager = ThemeManager.shared

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

                Text("Color Theme")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 12) {
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
                    .padding(.bottom, 32)
                }
            }
        }
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
