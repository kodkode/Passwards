import SwiftUI
import PasswardsCore

/// 1Password 8 visual language on iOS: brand azure, hero gradient, dark lock
/// surfaces, category/strength colors. Mirrors the macOS `Theme` identity (the
/// sRGB literals are cross-platform); appearance-adaptive colors use `UIColor`.
enum Theme {
    static let accent = Color(.sRGB, red: 0x05 / 255, green: 0x72 / 255, blue: 0xEC / 255)
    static let accentDeep = Color(.sRGB, red: 0x03 / 255, green: 0x64 / 255, blue: 0xD3 / 255)

    /// Lock screen / onboarding backdrop.
    static let heroGradient = LinearGradient(
        colors: [accentDeep, Color(.sRGB, red: 0x02 / 255, green: 0x2C / 255, blue: 0x66 / 255)],
        startPoint: .top, endPoint: .bottom
    )

    // Dark lock-screen surfaces (≈ 1P8 dark).
    static let lockBackdrop = Color(.sRGB, red: 0x22 / 255, green: 0x23 / 255, blue: 0x27 / 255)
    static let lockField = Color(.sRGB, red: 0x2B / 255, green: 0x2C / 255, blue: 0x32 / 255)
    static let lockFocus = Color(.sRGB, red: 0.45, green: 0.50, blue: 0.92)

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

extension Color {
    /// Appearance-adaptive color (resolves per light/dark at draw time).
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// The branded app mark used on the lock screen and onboarding. (Stands in for
/// the app icon until an iOS app-icon asset is added.)
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(
                LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: max(size / 40, 1))
            }
            .overlay {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: size / 30, y: size / 50)
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.35), radius: size / 8, y: size / 14)
    }
}

/// 1P8-style colored rounded-square tile: brand-color fill, a soft top→bottom
/// gradient + edge highlight, and a white SF Symbol glyph.
struct IconTile: View {
    let colorToken: String
    let symbol: String
    var size: CGFloat = 40

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.235, style: .continuous) }

    var body: some View {
        shape
            .fill(Theme.color(token: colorToken))
            .overlay {
                shape.fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.30), location: 0),
                        .init(color: .white.opacity(0.05), location: 0.55),
                        .init(color: .black.opacity(0.12), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: max(size / 32, 0.75)
                )
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: size / 40, y: size / 60)
            }
            .shadow(color: .black.opacity(0.2), radius: size / 28, y: size / 32)
    }
}

/// The category's tile (color + glyph).
struct CategoryIcon: View {
    let category: PasswardsCore.Category
    var size: CGFloat = 40
    var body: some View {
        IconTile(colorToken: category.colorToken, symbol: category.symbolName, size: size)
    }
}

/// The item's leading icon: a user-chosen custom symbol/color when set, else the
/// category tile. (Favicons are deferred for iOS v1.)
struct ItemIcon: View {
    let overview: ItemOverview
    var size: CGFloat = 40
    var body: some View {
        if let symbol = overview.iconSymbol, !symbol.isEmpty {
            IconTile(colorToken: overview.iconColor ?? overview.category.colorToken, symbol: symbol, size: size)
        } else {
            CategoryIcon(category: overview.category, size: size)
        }
    }
}

/// Five-segment password strength bar with label, as in the 1P8 generator.
struct StrengthBar: View {
    let score: PasswordStrength.Score
    var showLabel = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(index <= score.rawValue ? Theme.strengthColor(score) : Color.secondary.opacity(0.25))
                        .frame(height: 5)
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
