import SwiftUI
import UIKit
import PasswardsCore

/// iOS visual language — the **"playful" theme** from the Claude Design handoff
/// (`design_handoff_passwards_ios/`): Fredoka (rounded) headings + DM Sans body,
/// a lavender-white background with an indigo accent, big 28px cards, glossy icon
/// tiles, and a Sentinel speedometer. Adaptive light/dark (Settings → Appearance).
/// This is iOS-only; the macOS app stays a 1Password 8 clone.
enum Theme {
    static func hex(_ v: UInt) -> Color { Color(uiColor: UIColor(hex: v)) }

    // Accent (indigo/blue) — adaptive.
    static let accent = Color(light: UIColor(hex: 0x3E71E9), dark: UIColor(hex: 0x4F84FE))
    static let accentDeep = Color(light: UIColor(hex: 0x2C58C7), dark: UIColor(hex: 0x3E71E9))
    static let accentSoft = Color(light: UIColor(hex: 0xCDDEFF), dark: UIColor(hex: 0x233459)) // active pill / avatar bg
    static let accentText = Color(uiColor: UIColor(hex: 0xFCFCFC))                              // text/icon on accent
    static let link = accent

    // Surfaces.
    static let background = Color(light: UIColor(hex: 0xF3F4FF), dark: UIColor(hex: 0x0A0A12))  // app bg (lavender-white)
    static let surface = Color(light: UIColor(hex: 0xFEFFFF), dark: UIColor(hex: 0x14151F))     // cards / sheets
    static let surfaceHigh = Color(light: UIColor(hex: 0xE8EAF9), dark: UIColor(hex: 0x1F212C)) // inset inputs / chips
    static let surfaceLow = background
    static let cardBorder = Color(light: UIColor(hex: 0xD4D6E6), dark: UIColor(hex: 0x333441))  // hairline

    // Text.
    static let primaryLabel = Color(light: UIColor(hex: 0x12131B), dark: UIColor(hex: 0xF4F5FB))
    static let label = Color(light: UIColor(hex: 0x595A65), dark: UIColor(hex: 0x9FA1AC))        // muted
    static let labelDim = label

    // Semantic.
    static let danger = Color(uiColor: UIColor(hex: 0xE24947))   // Delete / Sign Out / errors
    static let warn = Color(uiColor: UIColor(hex: 0xE78C08))     // amber
    static let track = cardBorder                               // gauge / bar unfilled

    // Sentinel gauge palette (fixed).
    static let gaugeStops = [UIColor(hex: 0x2FB84B), UIColor(hex: 0x28C0BC), UIColor(hex: 0x3B9EFF)].map(Color.init)
    static let gaugePointer = Color(uiColor: UIColor(hex: 0x34C759))

    // Radii (playful).
    static let rCard: CGFloat = 28
    static let rBadge: CGFloat = 20
    static let rInput: CGFloat = 14
    static let rTile: CGFloat = 11        // item icon tile radius ratio ~ size*0.275
    static let rSheet: CGFloat = 34
    static let rTab: CGFloat = 26

    // Onboarding / lock share the app background in this theme (no navy hero).
    static let navy = background
    static let heroGradient = LinearGradient(colors: [accent, accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let lockBackdrop = background
    static let lockField = surfaceHigh
    static let lockFocus = accent

    /// Per-item / per-category tile colors (named tokens from `Category.colorToken`).
    static func color(token: String) -> Color {
        switch token {
        case "blue": hex(0x3B82F6)
        case "yellow": hex(0xF59E0B)
        case "teal": hex(0x0D9488)
        case "green": hex(0x22C55E)
        case "slate": hex(0x64748B)
        case "gray": hex(0x6B7280)
        case "indigo": hex(0x6366F1)
        case "mint": hex(0x10B981)
        case "orange": hex(0xF97316)
        case "purple": hex(0x8B5CF6)
        case "cyan": hex(0x06B6D4)
        case "sky": hex(0x0EA5E9)
        case "red": hex(0xEF4444)
        case "pink": hex(0xEC4899)
        case "forest": hex(0x16A34A)
        case "navy": hex(0x2563EB)
        case "magenta": hex(0xDB2777)
        case "steel": hex(0x475569)
        case "maroon": hex(0x9F1239)
        case "violet": hex(0x7C3AED)
        case "terminalGreen": hex(0x059669)
        case "aqua": hex(0x0891B2)
        default: accent
        }
    }

    static func strengthColor(_ score: PasswordStrength.Score) -> Color {
        switch score {
        case .terrible: hex(0xE24947)
        case .weak: hex(0xE78C08)
        case .fair: hex(0xEAB308)
        case .good: hex(0x6BAF3D)
        case .excellent: hex(0x25984D)
        }
    }

    // MARK: Fonts — Fredoka (rounded) heads/numbers · DM Sans body · mono for secrets.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Fredoka", size: size, relativeTo: .largeTitle).weight(weight)
    }
    static func title(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Fredoka", size: size, relativeTo: .title2).weight(weight)
    }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("DM Sans", size: size, relativeTo: .body).weight(weight)
    }
    static func caps(_ size: CGFloat = 12.5, _ weight: Font.Weight = .bold) -> Font {
        .custom("DM Sans", size: size, relativeTo: .caption).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Geist Mono", size: size, relativeTo: .body).weight(weight)
    }

    /// Transparent nav bar with Fredoka titles; the app bg shows through. Call once at launch.
    static func configureAppearance() {
        let bar = UINavigationBarAppearance()
        bar.configureWithTransparentBackground()
        func fredoka(_ size: CGFloat) -> UIFont {
            UIFont(name: "Fredoka-SemiBold", size: size) ?? UIFont(name: "Fredoka", size: size)
                ?? .systemFont(ofSize: size, weight: .semibold)
        }
        bar.titleTextAttributes = [.font: fredoka(17), .foregroundColor: UIColor.label]
        bar.largeTitleTextAttributes = [.font: fredoka(30), .foregroundColor: UIColor.label]
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

extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// Appearance-adaptive color (resolves per light/dark at draw time).
    ///
    /// `nonisolated` is load-bearing: the app target defaults to `@MainActor`
    /// isolation, which would make the `UIColor` dynamic-provider closure
    /// MainActor-isolated too. SwiftUI resolves colors on a background thread
    /// during async view-graph updates, so a MainActor closure there trips
    /// `dispatch_assert_queue` → SIGTRAP. Keeping it nonisolated lets UIKit call
    /// the provider on any thread safely.
    nonisolated init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

// MARK: - Shared components

/// The branded app mark (onboarding / lock): the handoff app-icon art when present,
/// else a generated indigo shield tile.
struct AppMark: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let mark = UIImage(named: "AppMark") {
                Image(uiImage: mark)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                    }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: size / 8, y: size / 12)
    }
}

/// Full-screen branded cover shown when the app is backgrounded / in the app
/// switcher, so an unlocked vault never appears in the multitasking snapshot.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            AppMark(size: 84)
        }
    }
}

/// Round initials avatar on an accentSoft fill (the shared header + Settings profile).
struct Avatar: View {
    var initials: String
    var size: CGFloat = 38

    var body: some View {
        Circle()
            .fill(Theme.accentSoft)
            .frame(width: size, height: size)
            .overlay {
                Text(initials.isEmpty ? "?" : initials)
                    .font(Theme.title(size * 0.4, .semibold))
                    .foregroundStyle(Theme.accent)
            }
    }
}

/// Glossy colored icon tile: brand-color fill + a top gloss highlight + white glyph.
/// This is the handoff's `GlossyIcon` (also used as the item/category leading icon).
struct IconTile: View {
    let colorToken: String
    let symbol: String
    var size: CGFloat = 44

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous) }

    var body: some View {
        shape
            .fill(Theme.color(token: colorToken))
            .overlay(alignment: .top) {
                // Gloss highlight (top ellipse), like the .dc.html tile.
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(height: size * 0.5)
                    .padding(.horizontal, size * 0.06)
                    .blur(radius: size * 0.02)
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: size / 40, y: size / 60)
            }
            .clipShape(shape)
            .shadow(color: Theme.color(token: colorToken).opacity(0.35), radius: size * 0.18, y: size * 0.1)
    }
}

/// A glossy tile carrying an arbitrary SF Symbol + explicit color (nudge/promo/tab uses).
struct GlossyIcon: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 44

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.25, style: .continuous) }

    var body: some View {
        shape.fill(color)
            .overlay(alignment: .top) {
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(height: size * 0.5).padding(.horizontal, size * 0.06).blur(radius: size * 0.02)
            }
            .frame(width: size, height: size)
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white) }
            .clipShape(shape)
            .shadow(color: color.opacity(0.35), radius: size * 0.18, y: size * 0.1)
    }
}

/// The category's glossy tile.
struct CategoryIcon: View {
    let category: PasswardsCore.Category
    var size: CGFloat = 44
    var body: some View { IconTile(colorToken: category.colorToken, symbol: category.symbolName, size: size) }
}

/// The item's leading icon. Precedence (matches macOS): custom symbol → favicon →
/// category tile. The favicon is a resolved `UIImage` injected by `IOSVaultModel`
/// (see `vault.favicon(for:)`), never fetched here — the view is fully stateless.
/// `favicon` defaults to nil so untouched call sites still compile and degrade to
/// the category tile.
struct ItemIcon: View {
    let overview: ItemOverview
    var favicon: UIImage? = nil
    var size: CGFloat = 44

    var body: some View {
        if let symbol = overview.iconSymbol, !symbol.isEmpty {
            IconTile(colorToken: overview.iconColor ?? overview.category.colorToken, symbol: symbol, size: size)
        } else if let favicon {
            FaviconImage(image: favicon, size: size)
        } else {
            CategoryIcon(category: overview.category, size: size)
        }
    }
}

/// Sentinel speedometer: a 270° open-bottom arc (green→teal→blue), tick notches,
/// and a triangle pointer at the score. Centered score number + uppercase label.
struct SentinelGauge: View {
    var score: Int                 // 0…100
    var label: String              // e.g. "EXCELLENT"
    var size: CGFloat = 232

    private let startDeg = 135.0
    private let sweepDeg = 270.0

    var body: some View {
        let stroke = size * 0.095
        ZStack {
            GaugeArc(startDeg: startDeg, sweepDeg: sweepDeg)
                .stroke(LinearGradient(colors: Theme.gaugeStops, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            GaugeTicks(startDeg: startDeg, sweepDeg: sweepDeg, count: 34)
                .stroke(Theme.background, style: StrokeStyle(lineWidth: max(2, size * 0.012), lineCap: .round))
            GaugePointer(startDeg: startDeg, sweepDeg: sweepDeg, fraction: pointerFraction, stroke: stroke)
                .fill(Theme.gaugePointer)
            VStack(spacing: 0) {
                Text("\(score)").font(Theme.display(size * 0.21, .semibold)).foregroundStyle(Theme.primaryLabel)
                Text(label.uppercased()).font(Theme.caps(size * 0.055, .bold)).tracking(1)
                    .foregroundStyle(Theme.label)
            }
            .offset(y: size * 0.10)
        }
        .frame(width: size, height: size * 0.82)   // open-bottom → shorter than wide
    }

    // High score → pointer on the left/green end (fraction 0 = start angle 135°).
    private var pointerFraction: Double { 1 - Double(max(0, min(100, score))) / 100 }
}

private nonisolated func gaugeGeometry(_ rect: CGRect) -> (center: CGPoint, r: CGFloat) {
    let r = rect.width * 0.44
    return (CGPoint(x: rect.midX, y: r + rect.width * 0.06), r)
}

private struct GaugeArc: Shape {
    let startDeg: Double, sweepDeg: Double
    func path(in rect: CGRect) -> Path {
        let (center, r) = gaugeGeometry(rect)
        var p = Path()
        p.addArc(center: center, radius: r,
                 startAngle: .degrees(startDeg), endAngle: .degrees(startDeg + sweepDeg), clockwise: false)
        return p
    }
}

private struct GaugeTicks: Shape {
    let startDeg: Double, sweepDeg: Double, count: Int
    func path(in rect: CGRect) -> Path {
        let (center, r) = gaugeGeometry(rect)
        var p = Path()
        let inner = r - rect.width * 0.045, outer = r + rect.width * 0.045
        for i in 0...count {
            let a = (startDeg + sweepDeg * Double(i) / Double(count)) * .pi / 180
            p.move(to: CGPoint(x: center.x + inner * cos(a), y: center.y + inner * sin(a)))
            p.addLine(to: CGPoint(x: center.x + outer * cos(a), y: center.y + outer * sin(a)))
        }
        return p
    }
}

private struct GaugePointer: Shape {
    let startDeg: Double, sweepDeg: Double, fraction: Double, stroke: CGFloat
    func path(in rect: CGRect) -> Path {
        let (center, r) = gaugeGeometry(rect)
        let a = (startDeg + sweepDeg * fraction) * .pi / 180
        let tipR = r - stroke * 0.5, baseR = r - stroke * 1.4, half = stroke * 0.42
        let tip = CGPoint(x: center.x + tipR * cos(a), y: center.y + tipR * sin(a))
        let bc = CGPoint(x: center.x + baseR * cos(a), y: center.y + baseR * sin(a))
        let perp = a + .pi / 2
        var p = Path()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: bc.x + half * cos(perp), y: bc.y + half * sin(perp)))
        p.addLine(to: CGPoint(x: bc.x - half * cos(perp), y: bc.y - half * sin(perp)))
        p.closeSubpath()
        return p
    }
}

/// Password-strength meter (playful): 4 rounded segments + label.
struct StrengthBar: View {
    let score: PasswordStrength.Score
    var showLabel = true

    private var filled: Int { min(4, score.rawValue) }   // 0…4 → up to 4 segments

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= filled ? Theme.strengthColor(score) : Theme.surfaceHigh)
                        .frame(height: 6)
                }
            }
            if showLabel {
                Text(score.label).font(Theme.text(12.5, .medium)).foregroundStyle(Theme.strengthColor(score))
            }
        }
    }
}
