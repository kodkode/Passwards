import SwiftUI
import UIKit
import PasswardsCore

/// Read view of an item: header (icon + title), filled fields with tap-to-copy /
/// reveal / live TOTP / open-URL, and notes. An Edit button opens the editor.
struct IOSItemDetailView: View {
    let vault: IOSVaultModel
    let itemID: String

    @State private var item: VaultItem?
    @State private var showEditor = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }.disabled(item == nil)
            }
        }
        .task(id: itemID) { item = await vault.item(id: itemID) }
        .sheet(isPresented: $showEditor, onDismiss: { Task { item = await vault.item(id: itemID) } }) {
            if let item {
                NavigationStack {
                    IOSItemEditorView(vault: vault, original: item, isNew: false, showsCancel: true,
                                      onClose: { showEditor = false })
                }
            }
        }
    }

    private func content(_ item: VaultItem) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ItemIcon(overview: item.overview, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.overview.title.isEmpty ? "Untitled" : item.overview.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Text(item.overview.category.displayName)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            ForEach(item.details.sections) { section in
                let fields = section.fields.filter { !$0.value.isEmpty }
                if !fields.isEmpty {
                    Section(section.title) {
                        ForEach(fields) { field in
                            IOSFieldRow(field: field, openURL: openURL)
                        }
                    }
                }
            }

            if !item.details.notes.isEmpty {
                Section("Notes") {
                    Text(item.details.notes).font(.body)
                }
            }
        }
    }
}

/// One field row: label + value, tap-to-copy, reveal for secrets, live TOTP, and
/// tappable URLs. Mirrors the macOS `FieldDisplayRow` interaction on iOS.
private struct IOSFieldRow: View {
    let field: ItemField
    let openURL: OpenURLAction

    @State private var revealed = false
    @State private var copied = false

    /// OTP renders its live code regardless, so only concealed/SSH fields get a
    /// reveal toggle.
    private var canReveal: Bool { field.kind == .concealed || field.kind == .sshKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(field.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark").font(.caption2).foregroundStyle(.green)
                } else if canReveal {
                    Button {
                        revealed.toggle()
                    } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye").font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            value
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { copy() }
    }

    @ViewBuilder private var value: some View {
        switch field.kind {
        case .concealed, .sshKey:
            if revealed {
                Text(coloredSecret(field.value))
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(field.kind == .sshKey ? 8 : 1)
            } else {
                Text(String(repeating: "•", count: min(max(field.value.count, 6), 16)))
                    .font(.body.monospaced())
            }
        case .otp:
            TOTPRow(secret: field.value)
        case .url:
            Button {
                if let url = normalizedURL(field.value) { openURL(url) }
            } label: {
                Text(field.value).foregroundStyle(Theme.accent).underline().lineLimit(1)
            }
            .buttonStyle(.plain)
        default:
            Text(field.value).font(.body)
        }
    }

    private func copy() {
        if field.kind == .otp, let gen = TOTPGenerator(userInput: field.value) {
            setClipboard(gen.code(), concealed: true)
        } else {
            setClipboard(field.value, concealed: field.kind.isSecret)
        }
        withAnimation { copied = true }
        Task { try? await Task.sleep(for: .seconds(1.2)); withAnimation { copied = false } }
    }
}

private struct TOTPRow: View {
    let secret: String
    var body: some View {
        if let gen = TOTPGenerator(userInput: secret) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let code = gen.code(at: ctx.date)
                let remaining = gen.secondsRemaining(at: ctx.date)
                HStack(spacing: 10) {
                    Text(grouped(code))
                        .font(.title3.monospaced().weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text("\(remaining)s")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(remaining <= 7 ? .orange : .secondary)
                }
            }
        } else {
            Label("Invalid one-time password", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        }
    }
    private func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }
}

private func coloredSecret(_ secret: String) -> AttributedString {
    var result = AttributedString()
    for ch in secret {
        var piece = AttributedString(String(ch))
        if ch.isNumber { piece.foregroundColor = Theme.accent }
        else if !ch.isLetter { piece.foregroundColor = Color(.sRGB, red: 0xE5 / 255, green: 0x3E / 255, blue: 0x3E / 255) }
        result += piece
    }
    return result
}

private func normalizedURL(_ s: String) -> URL? {
    URL(string: s.hasPrefix("http") ? s : "https://\(s)")
}

private func setClipboard(_ value: String, concealed: Bool) {
    if concealed {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": value]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)]
        )
    } else {
        UIPasteboard.general.string = value
    }
}
