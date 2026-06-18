import SwiftUI
import PasswardsCore

/// Mini-illustrations for category tiles, hand-drawn to approximate 1P8's
/// custom artwork: white "objects" with detail (cards, notes, coins, keys)
/// instead of flat symbols. Categories without bespoke art fall back to a
/// white SF Symbol.
struct CategoryGlyph: View {
    let category: PasswardsCore.Category
    let size: CGFloat

    var body: some View {
        switch category {
        case .login: LoginGlyph(s: size)
        case .secureNote: NoteGlyph(s: size)
        case .creditCard: CreditCardGlyph(s: size)
        case .identity: IDCardGlyph(s: size, accent: Color(.sRGB, red: 0.20, green: 0.70, blue: 0.32))
        case .driverLicense: IDCardGlyph(s: size, accent: Color(.sRGB, red: 0.05, green: 0.65, blue: 0.85))
        case .membership: IDCardGlyph(s: size, accent: Color(.sRGB, red: 0.92, green: 0.35, blue: 0.62))
        case .password: KeyGlyph(s: size)
        case .document: DocumentGlyph(s: size)
        case .apiCredential: CodeGlyph(s: size)
        case .bankAccount: CoinGlyph(s: size)
        case .cryptoWallet: WalletGlyph(s: size)
        case .database: DatabaseGlyph(s: size)
        case .emailAccount: EnvelopeGlyph(s: size)
        case .medicalRecord: MedicalGlyph(s: size)
        case .server: ServerGlyph(s: size)
        case .sshKey: TerminalGlyph(s: size)
        case .socialSecurityNumber: SSNGlyph(s: size)
        default:
            Image(systemName: category.symbolName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: size / 40, y: size / 36)
        }
    }
}

// MARK: - Shared pieces

private struct TextLines: View {
    let s: CGFloat
    var widths: [CGFloat]
    var color: Color = .black.opacity(0.22)

    var body: some View {
        VStack(alignment: .leading, spacing: s * 0.045) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule()
                    .fill(color)
                    .frame(width: s * width, height: s * 0.05)
            }
        }
    }
}

private func whiteCard(s: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat = 0.08) -> some View {
    RoundedRectangle(cornerRadius: s * r, style: .continuous)
        .fill(.white)
        .frame(width: s * w, height: s * h)
        .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
}

// MARK: - Glyphs

/// White ID card with avatar + lines, gold key overlapping the corner.
private struct LoginGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack {
            whiteCard(s: s, w: 0.62, h: 0.46)
                .overlay {
                    HStack(spacing: s * 0.05) {
                        Circle()
                            .fill(Color(.sRGB, red: 0.10, green: 0.46, blue: 0.92))
                            .frame(width: s * 0.16, height: s * 0.16)
                        TextLines(s: s, widths: [0.24, 0.17])
                    }
                    .padding(.horizontal, s * 0.06)
                }
            Image(systemName: "key.fill")
                .font(.system(size: s * 0.2, weight: .bold))
                .foregroundStyle(Color(.sRGB, red: 0.99, green: 0.78, blue: 0.18))
                .rotationEffect(.degrees(-45))
                .shadow(color: .black.opacity(0.35), radius: s * 0.015, y: s * 0.01)
                .offset(x: s * 0.22, y: s * 0.18)
        }
    }
}

/// Sticky note with a folded corner and text lines.
private struct NoteGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotchedSheet(foldFraction: 0.3)
                .fill(.white)
                .frame(width: s * 0.54, height: s * 0.58)
                .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
            // Folded corner
            FoldTriangle(foldFraction: 0.3)
                .fill(Color(.sRGB, red: 0.85, green: 0.68, blue: 0.05))
                .frame(width: s * 0.54, height: s * 0.58)
            TextLines(s: s, widths: [0.3, 0.3, 0.18])
                .frame(width: s * 0.54, height: s * 0.58, alignment: .bottomLeading)
                .padding(.leading, s * 0.07)
                .padding(.bottom, s * 0.08)
        }
        .frame(width: s * 0.54, height: s * 0.58)
    }
}

/// Sheet with the top-right corner cut off.
private struct NotchedSheet: Shape {
    var foldFraction: CGFloat
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * foldFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct FoldTriangle: Shape {
    var foldFraction: CGFloat
    func path(in rect: CGRect) -> Path {
        let fold = rect.width * foldFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
        path.closeSubpath()
        return path
    }
}

/// White card with gold chip and embossed number dots.
private struct CreditCardGlyph: View {
    let s: CGFloat
    var body: some View {
        whiteCard(s: s, w: 0.66, h: 0.44, r: 0.07)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: s * 0.02)
                    .fill(Color(.sRGB, red: 0.99, green: 0.78, blue: 0.18))
                    .frame(width: s * 0.13, height: s * 0.1)
                    .padding(.top, s * 0.08)
                    .padding(.leading, s * 0.07)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: s * 0.035) {
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: s * 0.015) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .fill(.black.opacity(0.25))
                                    .frame(width: s * 0.03, height: s * 0.03)
                            }
                        }
                    }
                }
                .padding(.bottom, s * 0.08)
                .padding(.leading, s * 0.07)
            }
    }
}

/// Generic ID-style card: tinted avatar + lines (identity, licenses, memberships).
private struct IDCardGlyph: View {
    let s: CGFloat
    let accent: Color
    var body: some View {
        whiteCard(s: s, w: 0.64, h: 0.46, r: 0.07)
            .overlay {
                HStack(spacing: s * 0.05) {
                    VStack(spacing: s * 0.02) {
                        Circle()
                            .fill(accent)
                            .frame(width: s * 0.13, height: s * 0.13)
                        Capsule()
                            .fill(accent.opacity(0.5))
                            .frame(width: s * 0.15, height: s * 0.045)
                    }
                    TextLines(s: s, widths: [0.22, 0.16, 0.20])
                }
                .padding(.horizontal, s * 0.06)
            }
    }
}

/// Round-head key, white, diagonal.
private struct KeyGlyph: View {
    let s: CGFloat
    var body: some View {
        Image(systemName: "key.fill")
            .font(.system(size: s * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(-45))
            .shadow(color: .black.opacity(0.3), radius: s / 40, y: s / 36)
    }
}

/// Paper sheet with folded corner and lines.
private struct DocumentGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack(alignment: .topTrailing) {
            NotchedSheet(foldFraction: 0.32)
                .fill(.white)
                .frame(width: s * 0.46, height: s * 0.58)
                .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
            FoldTriangle(foldFraction: 0.32)
                .fill(.black.opacity(0.18))
                .frame(width: s * 0.46, height: s * 0.58)
            TextLines(s: s, widths: [0.26, 0.26, 0.16])
                .frame(width: s * 0.46, height: s * 0.58, alignment: .bottomLeading)
                .padding(.leading, s * 0.06)
                .padding(.bottom, s * 0.08)
        }
        .frame(width: s * 0.46, height: s * 0.58)
    }
}

/// `</>` mono code marks.
private struct CodeGlyph: View {
    let s: CGFloat
    var body: some View {
        Text("</>")
            .font(.system(size: s * 0.3, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: s / 40, y: s / 36)
    }
}

/// Gold coin with $.
private struct CoinGlyph: View {
    let s: CGFloat
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(.sRGB, red: 1.0, green: 0.85, blue: 0.35),
                        Color(.sRGB, red: 0.93, green: 0.68, blue: 0.10),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: s * 0.56, height: s * 0.56)
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.55), lineWidth: s * 0.025)
                    .padding(s * 0.05)
            }
            .overlay {
                Text("$")
                    .font(.system(size: s * 0.3, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(.sRGB, red: 0.55, green: 0.36, blue: 0.02))
            }
            .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
    }
}

/// Wallet with flap and gold clasp.
private struct WalletGlyph: View {
    let s: CGFloat
    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
                .fill(.white)
                .frame(width: s * 0.6, height: s * 0.44)
                .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
            RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
                .fill(.black.opacity(0.15))
                .frame(width: s * 0.26, height: s * 0.2)
                .overlay {
                    Circle()
                        .fill(Color(.sRGB, red: 0.99, green: 0.78, blue: 0.18))
                        .frame(width: s * 0.09, height: s * 0.09)
                }
                .padding(.trailing, s * 0.04)
        }
    }
}

/// Stacked database cylinder.
private struct DatabaseGlyph: View {
    let s: CGFloat
    var body: some View {
        VStack(spacing: s * 0.035) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
                    .fill(.white.opacity(index == 0 ? 1 : 0.85))
                    .frame(width: s * 0.52, height: s * 0.15)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
    }
}

/// Envelope with visible flap fold.
private struct EnvelopeGlyph: View {
    let s: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: s * 0.05, style: .continuous)
            .fill(.white)
            .frame(width: s * 0.6, height: s * 0.42)
            .overlay {
                FlapShape()
                    .stroke(.black.opacity(0.25), lineWidth: s * 0.028)
                    .padding(s * 0.02)
            }
            .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
    }

    private struct FlapShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.1))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            return path
        }
    }
}

/// White rounded square with red cross.
private struct MedicalGlyph: View {
    let s: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: s * 0.09, style: .continuous)
            .fill(.white)
            .frame(width: s * 0.5, height: s * 0.5)
            .overlay {
                ZStack {
                    Capsule()
                        .fill(Color(.sRGB, red: 0.88, green: 0.25, blue: 0.25))
                        .frame(width: s * 0.3, height: s * 0.105)
                    Capsule()
                        .fill(Color(.sRGB, red: 0.88, green: 0.25, blue: 0.25))
                        .frame(width: s * 0.105, height: s * 0.3)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
    }
}

/// Two rack units with status lights.
private struct ServerGlyph: View {
    let s: CGFloat
    var body: some View {
        VStack(spacing: s * 0.04) {
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: s * 0.04, style: .continuous)
                    .fill(.white)
                    .frame(width: s * 0.58, height: s * 0.18)
                    .overlay(alignment: .leading) {
                        HStack(spacing: s * 0.03) {
                            Circle()
                                .fill(Color(.sRGB, red: 0.20, green: 0.78, blue: 0.35))
                                .frame(width: s * 0.05, height: s * 0.05)
                            Capsule()
                                .fill(.black.opacity(0.2))
                                .frame(width: s * 0.2, height: s * 0.045)
                        }
                        .padding(.leading, s * 0.06)
                    }
            }
        }
        .shadow(color: .black.opacity(0.25), radius: s * 0.02, y: s * 0.015)
    }
}

/// Terminal window with green prompt.
private struct TerminalGlyph: View {
    let s: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
            .fill(.black.opacity(0.45))
            .frame(width: s * 0.6, height: s * 0.46)
            .overlay {
                RoundedRectangle(cornerRadius: s * 0.07, style: .continuous)
                    .strokeBorder(.white.opacity(0.7), lineWidth: s * 0.025)
            }
            .overlay(alignment: .topLeading) {
                Text("❯_")
                    .font(.system(size: s * 0.18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(.sRGB, red: 0.35, green: 0.95, blue: 0.55))
                    .padding(.top, s * 0.08)
                    .padding(.leading, s * 0.07)
            }
    }
}

/// Shield card with masked digits.
private struct SSNGlyph: View {
    let s: CGFloat
    var body: some View {
        whiteCard(s: s, w: 0.6, h: 0.44, r: 0.07)
            .overlay {
                VStack(spacing: s * 0.05) {
                    HStack(spacing: s * 0.025) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle()
                                .fill(.black.opacity(0.3))
                                .frame(width: s * 0.045, height: s * 0.045)
                        }
                    }
                    Capsule()
                        .fill(.black.opacity(0.18))
                        .frame(width: s * 0.3, height: s * 0.05)
                }
            }
    }
}
