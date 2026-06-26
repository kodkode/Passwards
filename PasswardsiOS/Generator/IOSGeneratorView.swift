import SwiftUI
import UIKit
import PasswardsCore

/// 1P8-style password generator: random / memorable / PIN, with a live strength
/// bar and copy. (Cross-platform generator logic from `PasswordGenerator`.)
struct IOSGeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case random = "Random", memorable = "Memorable", pin = "PIN"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .random
    @State private var output = ""
    @State private var copied = false

    // Random
    @State private var length: Double = 20
    @State private var includeNumbers = true
    @State private var includeSymbols = true
    // Memorable
    @State private var wordCount: Double = 4
    @State private var separator: PasswordGenerator.Separator = .hyphens
    @State private var capitalize = false
    // PIN
    @State private var pinLength: Double = 6

    private var score: PasswordStrength.Score { PasswordStrength.score(output) }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Text("GENERATED PASSWORD").font(Theme.caps(11)).tracking(0.5).foregroundStyle(Theme.labelDim)
                    Text(coloredOutput)
                        .font(Theme.mono(22, .semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if !output.isEmpty {
                        HStack(spacing: 8) {
                            Text(score.label.uppercased()).font(Theme.caps(11)).foregroundStyle(Theme.strengthColor(score))
                            StrengthBar(score: score, showLabel: false)
                        }
                    }
                    HStack(spacing: 12) {
                        Button { regenerate() } label: {
                            Label("Regenerate", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(Theme.label)
                        Button {
                            UIPasteboard.general.string = output
                            withAnimation { copied = true }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(copied ? Theme.accent : Theme.link)
                    }
                    .font(Theme.text(15, .semibold))
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
            }

            Picker("Type", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            switch mode {
            case .random:
                Section {
                    Stepper("Length: \(Int(length))", value: $length, in: 8...100)
                    Toggle("Numbers", isOn: $includeNumbers).tint(Theme.link)
                    Toggle("Symbols", isOn: $includeSymbols).tint(Theme.link)
                } header: { Text("OPTIONS").font(Theme.caps(11)).foregroundStyle(Theme.labelDim) }
                .listRowBackground(Theme.surface)
            case .memorable:
                Section {
                    Stepper("Words: \(Int(wordCount))", value: $wordCount, in: 3...15)
                    Picker("Separator", selection: $separator) {
                        ForEach(PasswordGenerator.Separator.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Capitalize", isOn: $capitalize).tint(Theme.link)
                } header: { Text("OPTIONS").font(Theme.caps(11)).foregroundStyle(Theme.labelDim) }
                .listRowBackground(Theme.surface)
            case .pin:
                Section {
                    Stepper("Digits: \(Int(pinLength))", value: $pinLength, in: 3...12)
                } header: { Text("OPTIONS").font(Theme.caps(11)).foregroundStyle(Theme.labelDim) }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Generator")
        .onAppear { if output.isEmpty { regenerate() } }
        .onChange(of: mode) { _, _ in regenerate() }
        .onChange(of: length) { _, _ in if mode == .random { regenerate() } }
        .onChange(of: includeNumbers) { _, _ in regenerate() }
        .onChange(of: includeSymbols) { _, _ in regenerate() }
        .onChange(of: wordCount) { _, _ in if mode == .memorable { regenerate() } }
        .onChange(of: separator) { _, _ in regenerate() }
        .onChange(of: capitalize) { _, _ in regenerate() }
        .onChange(of: pinLength) { _, _ in if mode == .pin { regenerate() } }
    }

    private var coloredOutput: AttributedString {
        var result = AttributedString()
        for ch in output {
            var piece = AttributedString(String(ch))
            if ch.isNumber {
                piece.foregroundColor = Theme.accent
            } else if !ch.isLetter {
                piece.foregroundColor = Color(.sRGB, red: 0xE5 / 255, green: 0x3E / 255, blue: 0x3E / 255)
            }
            result += piece
        }
        return result
    }

    private func regenerate() {
        copied = false
        switch mode {
        case .random:
            output = PasswordGenerator.random(.init(length: Int(length), includeNumbers: includeNumbers, includeSymbols: includeSymbols))
        case .memorable:
            output = PasswordGenerator.memorable(.init(wordCount: Int(wordCount), separator: separator, capitalize: capitalize))
        case .pin:
            output = PasswordGenerator.pin(length: Int(pinLength))
        }
    }
}
