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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }.disabled(item == nil).tint(Theme.accent)
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
                VStack(spacing: 10) {
                    ItemIcon(overview: item.overview, size: 64)
                    Text(item.overview.title.isEmpty ? "Untitled" : item.overview.title)
                        .font(Theme.title(24, .bold)).foregroundStyle(.white)
                        .multilineTextAlignment(.center).lineLimit(2)
                    Text(item.overview.category.displayName)
                        .font(Theme.text(14)).foregroundStyle(Theme.labelDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            ForEach(item.details.sections) { section in
                let fields = section.fields.filter { !$0.value.isEmpty }
                if !fields.isEmpty {
                    Section {
                        ForEach(fields) { field in
                            IOSFieldRow(field: field, openURL: openURL).listRowBackground(Theme.surface)
                        }
                    } header: {
                        if !section.title.isEmpty { sectionLabel(section.title) }
                    }
                }
            }

            if !item.details.notes.isEmpty {
                Section {
                    Text(item.details.notes).font(Theme.text(15)).listRowBackground(Theme.surface)
                } header: { sectionLabel("Notes") }
            }

            Section {
                Button {
                    if let summary = vault.summaries.first(where: { $0.id == item.id }) {
                        Task { await vault.moveToTrash(summary); dismiss() }
                    }
                } label: {
                    Text("Delete Item").font(Theme.text(16, .semibold))
                        .foregroundStyle(Theme.danger).frame(maxWidth: .infinity)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(Theme.caps(11)).foregroundStyle(Theme.labelDim).tracking(0.5)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(field.label.uppercased())
                    .font(Theme.caps(11)).tracking(0.5)
                    .foregroundStyle(Theme.labelDim)
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark").font(Theme.caps(11)).foregroundStyle(Theme.accent)
                } else {
                    HStack(spacing: 14) {
                        if canReveal {
                            Button { revealed.toggle() } label: {
                                Image(systemName: revealed ? "eye.slash" : "eye").font(.callout)
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.labelDim)
                        }
                        Image(systemName: "doc.on.doc").font(.callout).foregroundStyle(Theme.labelDim)
                    }
                }
            }
            value
            if field.purpose == .password, !field.value.isEmpty {
                let score = PasswordStrength.score(field.value)
                HStack(spacing: 8) {
                    Text(score.label.uppercased()).font(Theme.caps(10))
                        .foregroundStyle(Theme.strengthColor(score))
                    StrengthBar(score: score, showLabel: false)
                }
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { copy() }
    }

    @ViewBuilder private var value: some View {
        switch field.kind {
        case .concealed, .sshKey:
            if revealed {
                Text(coloredSecret(field.value))
                    .font(Theme.mono(15))
                    .textSelection(.enabled)
                    .lineLimit(field.kind == .sshKey ? 8 : 1)
            } else {
                Text(String(repeating: "•", count: min(max(field.value.count, 6), 16)))
                    .font(Theme.mono(15))
            }
        case .otp:
            TOTPRow(secret: field.value)
        case .url:
            Button {
                if let url = normalizedURL(field.value) { openURL(url) }
            } label: {
                Text(field.value).font(Theme.text(16)).foregroundStyle(Theme.link).underline().lineLimit(1)
            }
            .buttonStyle(.plain)
        default:
            Text(field.value).font(Theme.text(16)).foregroundStyle(.white)
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
                        .font(Theme.mono(20, .semibold))
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
