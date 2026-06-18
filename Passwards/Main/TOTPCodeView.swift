import SwiftUI
import PasswardsCore

/// Live TOTP code, grouped in threes, with a 30-second countdown ring.
struct TOTPCodeView: View {
    let secretInput: String

    var body: some View {
        if let generator = TOTPGenerator(userInput: secretInput) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let code = generator.code(at: context.date)
                let remaining = generator.secondsRemaining(at: context.date)
                HStack(spacing: 10) {
                    Text(groupedCode(code))
                        .font(.title3.monospaced().weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    CountdownRing(
                        progress: Double(remaining) / Double(generator.period),
                        warning: remaining <= 7
                    )
                    .frame(width: 18, height: 18)
                    Text("\(remaining)s")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .leading)
                }
            }
        } else {
            Label("Invalid one-time password secret", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private func groupedCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return code.prefix(3) + " " + code.suffix(3)
    }
}

struct CountdownRing: View {
    let progress: Double
    let warning: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    warning ? Color.orange : Theme.accent,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}
