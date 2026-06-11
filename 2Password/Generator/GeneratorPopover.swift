import SwiftUI
import TwoPasswordCore

/// The three-mode password generator: Random / Memorable / PIN, with the
/// colored-character preview and strength meter, like 1P8's generator panel.
struct GeneratorPopover: View {
    enum Context {
        case standalone
        case filling((String) -> Void)
    }

    let context: Context
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case random = "Random"
        case memorable = "Memorable"
        case pin = "PIN"
        var id: String { rawValue }
    }

    @AppStorage("generatorMode") private var modeRaw = Mode.random.rawValue
    @AppStorage("generatorLength") private var length = 20
    @AppStorage("generatorNumbers") private var includeNumbers = true
    @AppStorage("generatorSymbols") private var includeSymbols = true
    @AppStorage("generatorWordCount") private var wordCount = 4
    @AppStorage("generatorSeparator") private var separatorRaw = PasswordGenerator.Separator.hyphens.rawValue
    @AppStorage("generatorCapitalize") private var capitalize = false
    @AppStorage("generatorFullWords") private var fullWords = true
    @AppStorage("generatorPinLength") private var pinLength = 6

    @State private var password = ""
    @State private var copied = false

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .random }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Preview
            HStack {
                Text(Theme.coloredPassword(password, font: .title3.monospaced()))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    regenerate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Regenerate")
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if mode != .pin {
                StrengthBar(score: PasswordStrength.score(password))
            }

            Picker("", selection: $modeRaw) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.rawValue).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .random:
                HStack {
                    Text("Characters: \(length)")
                        .font(.callout)
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(length) },
                        set: { length = Int($0) }
                    ), in: 8...100, step: 1)
                }
                Toggle("Numbers", isOn: $includeNumbers)
                Toggle("Symbols", isOn: $includeSymbols)
            case .memorable:
                HStack {
                    Text("Words: \(wordCount)")
                        .font(.callout)
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(wordCount) },
                        set: { wordCount = Int($0) }
                    ), in: 3...15, step: 1)
                }
                Picker("Separator", selection: $separatorRaw) {
                    ForEach(PasswordGenerator.Separator.allCases) { separator in
                        Text(separator.displayName).tag(separator.rawValue)
                    }
                }
                Toggle("Capitalize", isOn: $capitalize)
                Toggle("Full words", isOn: $fullWords)
            case .pin:
                HStack {
                    Text("Digits: \(pinLength)")
                        .font(.callout)
                        .frame(width: 110, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(pinLength) },
                        set: { pinLength = Int($0) }
                    ), in: 3...12, step: 1)
                }
            }

            HStack {
                Button {
                    ClipboardManager.copy(password, concealed: true)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.2))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Spacer()
                if case .filling(let fill) = context {
                    Button("Use Password") {
                        fill(password)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
        .onAppear(perform: regenerate)
        .onChange(of: modeRaw) { regenerate() }
        .onChange(of: length) { regenerate() }
        .onChange(of: includeNumbers) { regenerate() }
        .onChange(of: includeSymbols) { regenerate() }
        .onChange(of: wordCount) { regenerate() }
        .onChange(of: separatorRaw) { regenerate() }
        .onChange(of: capitalize) { regenerate() }
        .onChange(of: fullWords) { regenerate() }
        .onChange(of: pinLength) { regenerate() }
    }

    private func regenerate() {
        switch mode {
        case .random:
            password = PasswordGenerator.random(.init(length: length, includeNumbers: includeNumbers, includeSymbols: includeSymbols))
        case .memorable:
            let separator = PasswordGenerator.Separator(rawValue: separatorRaw) ?? .hyphens
            password = PasswordGenerator.memorable(.init(wordCount: wordCount, separator: separator, capitalize: capitalize, fullWords: fullWords))
        case .pin:
            password = PasswordGenerator.pin(length: pinLength)
        }
    }
}
