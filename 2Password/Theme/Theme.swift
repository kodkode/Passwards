import SwiftUI
import TwoPasswordCore

/// 1Password 8 visual language: brand blues, dark surfaces, category colors.
enum Theme {
    // Brand
    static let accent = Color(.sRGB, red: 0x05 / 255, green: 0x72 / 255, blue: 0xEC / 255) // Azure Radiance
    static let accentDeep = Color(.sRGB, red: 0x03 / 255, green: 0x64 / 255, blue: 0xD3 / 255) // Science Blue
    static let shark = Color(.sRGB, red: 0x30 / 255, green: 0x31 / 255, blue: 0x36 / 255)

    /// Lock screen / onboarding backdrop.
    static let heroGradient = LinearGradient(
        colors: [accentDeep, Color(.sRGB, red: 0x02 / 255, green: 0x2C / 255, blue: 0x66 / 255)],
        startPoint: .top, endPoint: .bottom
    )

    // Dark theme surfaces (≈ 1P8)
    static let windowDark = Color(.sRGB, red: 0x1F / 255, green: 0x20 / 255, blue: 0x23 / 255)
    static let cardDark = Color(.sRGB, red: 0x2A / 255, green: 0x2C / 255, blue: 0x30 / 255)

    /// Password character coloring, same rule as 1P8: digits blue, symbols red.
    static func coloredPassword(_ password: String, font: Font = .body.monospaced()) -> AttributedString {
        var result = AttributedString()
        for char in password {
            var piece = AttributedString(String(char))
            if char.isNumber {
                piece.foregroundColor = accent
            } else if !char.isLetter {
                piece.foregroundColor = Color(.sRGB, red: 0xE5 / 255, green: 0x3E / 255, blue: 0x3E / 255)
            }
            result += piece
        }
        result.font = font
        return result
    }

    /// Category icon background colors, keyed by `Category.colorToken`.
    static func color(token: String) -> Color {
        switch token {
        case "blue": Color(.sRGB, red: 0.10, green: 0.46, blue: 0.92)
        case "yellow": Color(.sRGB, red: 0.95, green: 0.77, blue: 0.06)
        case "teal": Color(.sRGB, red: 0.00, green: 0.65, blue: 0.65)
        case "green": Color(.sRGB, red: 0.20, green: 0.70, blue: 0.32)
        case "slate": Color(.sRGB, red: 0.42, green: 0.46, blue: 0.55)
        case "gray": Color(.sRGB, red: 0.50, green: 0.52, blue: 0.56)
        case "indigo": Color(.sRGB, red: 0.35, green: 0.34, blue: 0.84)
        case "mint": Color(.sRGB, red: 0.00, green: 0.78, blue: 0.58)
        case "orange": Color(.sRGB, red: 0.95, green: 0.52, blue: 0.11)
        case "purple": Color(.sRGB, red: 0.58, green: 0.35, blue: 0.84)
        case "cyan": Color(.sRGB, red: 0.05, green: 0.65, blue: 0.85)
        case "sky": Color(.sRGB, red: 0.25, green: 0.61, blue: 0.95)
        case "red": Color(.sRGB, red: 0.88, green: 0.25, blue: 0.25)
        case "pink": Color(.sRGB, red: 0.92, green: 0.35, blue: 0.62)
        case "forest": Color(.sRGB, red: 0.13, green: 0.55, blue: 0.27)
        case "navy": Color(.sRGB, red: 0.13, green: 0.25, blue: 0.55)
        case "magenta": Color(.sRGB, red: 0.78, green: 0.22, blue: 0.65)
        case "steel": Color(.sRGB, red: 0.35, green: 0.42, blue: 0.50)
        case "maroon": Color(.sRGB, red: 0.55, green: 0.18, blue: 0.25)
        case "violet": Color(.sRGB, red: 0.48, green: 0.28, blue: 0.78)
        case "terminalGreen": Color(.sRGB, red: 0.12, green: 0.60, blue: 0.40)
        case "aqua": Color(.sRGB, red: 0.10, green: 0.58, blue: 0.72)
        default: accent
        }
    }

    static func strengthColor(_ score: PasswordStrength.Score) -> Color {
        switch score {
        case .terrible: Color(.sRGB, red: 0.88, green: 0.25, blue: 0.25)
        case .weak: Color(.sRGB, red: 0.95, green: 0.52, blue: 0.11)
        case .fair: Color(.sRGB, red: 0.95, green: 0.77, blue: 0.06)
        case .good: Color(.sRGB, red: 0.45, green: 0.75, blue: 0.25)
        case .excellent: Color(.sRGB, red: 0.20, green: 0.70, blue: 0.32)
        }
    }
}

/// The colored rounded-square category icon used in lists and headers.
struct CategoryIconView: View {
    let category: TwoPasswordCore.Category
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Theme.color(token: category.colorToken).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: category.symbolName)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// Five-segment password strength bar with label, as in the 1P8 generator.
struct StrengthBar: View {
    let score: PasswordStrength.Score
    var showLabel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(index <= score.rawValue ? Theme.strengthColor(score) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            if showLabel {
                Text(score.label)
                    .font(.caption)
                    .foregroundStyle(Theme.strengthColor(score))
            }
        }
    }
}
