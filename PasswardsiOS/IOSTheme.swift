import SwiftUI
import UIKit
import PasswardsCore

/// "Vault Sentinel" — the iOS design system from the owner's Stitch
/// "SecurePass Mobile Vault": deep-navy / near-black dark surfaces, Security Green
/// as the primary accent (active tab, FAB, strength, positive states), and an
/// iOS blue for links / secondary actions. Dark-first.
enum Theme {
    static func hex(_ v: UInt) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    // Brand accents
    static let accent = hex(0x10B981)       // Security Green
    static let accentDeep = hex(0x059669)
    static let link = hex(0x60A5FA)         // iOS blue — links / secondary actions

    // Dark surfaces
    static let background = hex(0x101216)   // app base (near-black)
    static let navy = hex(0x0A192F)         // deep navy (hero / lock)
    static let surface = hex(0x1C1D22)      // cards
    static let surfaceHigh = hex(0x26272D)  // raised / chips / fields
    static let surfaceLow = hex(0x16171B)
    static let cardBorder = Color.white.opacity(0.06)
    static let label = hex(0xC5C6CD)        // primary gray text
    static let labelDim = hex(0x83858E)     // dim / uppercase labels
    static let danger = hex(0xFF6B6B)

    /// Hero / lock backdrop: deep navy fading to near-black.
    static let heroGradient = LinearGradient(
        colors: [hex(0x0A192F), hex(0x070D17)], startPoint: .top, endPoint: .bottom
    )

    static let lockBackdrop = background
    static let lockField = surfaceHigh
    static let lockFocus = accent

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

    // MARK: Fonts (Vault Sentinel)
    // Hanken Grotesk → headlines/body · Geist → uppercase labels · Geist Mono →
    // passwords, TOTP codes, Secret Key. `relativeTo` keeps Dynamic Type scaling.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Hanken Grotesk", size: size, relativeTo: .largeTitle).weight(weight)
    }
    static func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Hanken Grotesk", size: size, relativeTo: .title2).weight(weight)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Hanken Grotesk", size: size, relativeTo: .body).weight(weight)
    }
    static func caps(_ size: CGFloat = 12, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Geist", size: size, relativeTo: .caption).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Geist Mono", size: size, relativeTo: .body).weight(weight)
    }

    /// Dark, blended navigation bar with Hanken Grotesk titles. Call once at launch.
    static func configureAppearance() {
        let bar = UINavigationBarAppearance()
        bar.configureWithOpaqueBackground()
        bar.backgroundColor = UIColor(background)
        bar.shadowColor = .clear
        func hanken(_ size: CGFloat, _ w: UIFont.Weight) -> UIFont {
            let base = UIFont(name: "Hanken Grotesk", size: size) ?? .systemFont(ofSize: size, weight: w)
            let d = base.fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: w]])
            return UIFont(descriptor: d, size: size)
        }
        bar.largeTitleTextAttributes = [.font: hanken(32, .bold), .foregroundColor: UIColor.white]
        bar.titleTextAttributes = [.font: hanken(17, .semibold), .foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
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

/// The branded app mark (lock screen / onboarding): the real app-icon art when
/// the `AppMark` asset is present, else a generated azure lock tile.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let mark = UIImage(named: "AppMark") {
                Image(uiImage: mark)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: max(size / 60, 0.5))
                    }
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: size * 0.5, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
            }
        }
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

/// The item's leading icon. Precedence (matches macOS): a user-chosen custom
/// symbol → the site favicon (when a URL exists) → the category tile.
struct ItemIcon: View {
    let overview: ItemOverview
    var size: CGFloat = 40
    var body: some View {
        if let symbol = overview.iconSymbol, !symbol.isEmpty {
            IconTile(colorToken: overview.iconColor ?? overview.category.colorToken, symbol: symbol, size: size)
        } else if let url = overview.urls.first, !url.isEmpty {
            FaviconView(urlString: url, fallback: overview.category, size: size)
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
