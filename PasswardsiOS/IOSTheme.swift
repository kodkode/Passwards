import SwiftUI
import UIKit
import PasswardsCore

/// iOS visual language — a faithful port of the macOS 1Password 8 clone: the
/// system font (SF Pro), 1Password's azure-blue accent, and **adaptive light/dark
/// surfaces** built on iOS's native grouped-list semantics (white cards on a light
/// gray base; `#1C1C1E` cards on black in dark). The lock/onboarding stay branded
/// navy like the Mac. The user picks Light / Dark / System in Settings.
enum Theme {
    static func hex(_ v: UInt) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    // Brand accents (1Password) — constant across light & dark.
    static let accent = hex(0x0572EC)       // Azure Radiance (1P blue)
    static let accentDeep = hex(0x0364D3)    // Science Blue
    static let link = accent                 // links use the brand blue

    // Adaptive surfaces (native iOS grouped look).
    static let background = Color(uiColor: .systemGroupedBackground)        // light #F2F2F7 / dark #000
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)  // light #FFF / dark #1C1C1E
    static let surfaceHigh = Color(light: UIColor(white: 0.92, alpha: 1),   // chips / fields / raised
                                   dark: UIColor(red: 0x2C/255, green: 0x2C/255, blue: 0x2E/255, alpha: 1))
    static let surfaceLow = Color(uiColor: .systemGroupedBackground)
    static let cardBorder = Color(uiColor: .separator)

    // Text (semantic — adapts automatically).
    static let primaryLabel = Color(uiColor: .label)
    static let label = Color(uiColor: .secondaryLabel)
    static let labelDim = Color(uiColor: .tertiaryLabel)

    static let danger = Color(uiColor: .systemRed)
    static let warn = Color(uiColor: .systemOrange)
    static let track = Color(uiColor: .systemGray5)   // gauge / bar unfilled track

    // Lock / onboarding stay branded navy (like the Mac lock screen) in both modes.
    static let navy = hex(0x0A192F)
    static let heroGradient = LinearGradient(
        colors: [hex(0x0364D3), hex(0x022C66)], startPoint: .top, endPoint: .bottom
    )
    static let lockBackdrop = hex(0x0A192F)
    static let lockField = Color.white.opacity(0.12)
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

    // MARK: Fonts — Apple's system font (SF Pro / SF Mono), like 1Password.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    static func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func caps(_ size: CGFloat = 12, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Native translucent navigation bar that adapts to light/dark. Call once at launch.
    static func configureAppearance() {
        let bar = UINavigationBarAppearance()
        bar.configureWithDefaultBackground()
        bar.titleTextAttributes = [.foregroundColor: UIColor.label]
        bar.largeTitleTextAttributes = [.foregroundColor: UIColor.label]
        UINavigationBar.appearance().standardAppearance = bar
        UINavigationBar.appearance().scrollEdgeAppearance = bar
        UINavigationBar.appearance().compactAppearance = bar
    }
}

/// User appearance preference (Settings → Appearance), persisted via `@AppStorage`.
enum IOSAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "ios.appearance"
    var id: String { rawValue }
    var label: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
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
        .shadow(color: .black.opacity(0.25), radius: size / 8, y: size / 14)
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
            .shadow(color: .black.opacity(0.12), radius: size / 28, y: size / 32)
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

/// Circular score gauge (Watchtower): a colored arc filled to `fraction`, with a
/// centered big number + uppercase label. Used on the Vault Home card + Security.
struct CircularGauge: View {
    let fraction: Double          // 0…1
    let value: String             // e.g. "92"
    let label: String             // e.g. "EXCELLENT"
    var color: Color = Theme.accent
    var size: CGFloat = 128
    var valueFont: CGFloat = 34
    var labelColor: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, lineWidth: size * 0.075)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: size * 0.075, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(value).font(Theme.display(valueFont, .heavy)).foregroundStyle(Theme.primaryLabel)
                Text(label.uppercased()).font(Theme.caps(11)).tracking(0.8).foregroundStyle(labelColor)
            }
        }
        .frame(width: size, height: size)
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
