import SwiftUI
import UIKit
import PasswardsCore

/// Read view of an item (playful): hero icon + title, a grouped card of type-aware
/// fields (tap-to-copy / reveal / live TOTP / open-URL), notes, a Watchtower warning
/// card, and a destructive Delete. Works both as a sheet root and pushed in a list.
struct IOSItemDetailView: View {
    let vault: IOSVaultModel
    let itemID: String
    var watchtower: IOSWatchtowerModel? = nil

    @State private var item: VaultItem?
    @State private var showEditor = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let item { content(item) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.background)
        .navigationTitle(item?.overview.category.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark").fontWeight(.semibold) }.tint(Theme.label)
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let summary = vault.summaries.first(where: { $0.id == itemID }) {
                    Button { Task { await vault.toggleFavorite(summary) } } label: {
                        Image(systemName: summary.overview.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(summary.overview.isFavorite ? Theme.warn : Theme.label)
                    }
                }
            }
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
                .presentationCornerRadius(Theme.rSheet)
            }
        }
    }

    private func content(_ item: VaultItem) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ItemIcon(overview: item.overview, favicon: vault.favicon(for: item.overview), size: 68)
                    Text(item.overview.title.isEmpty ? "Untitled" : item.overview.title)
                        .font(Theme.title(24, .semibold)).foregroundStyle(Theme.primaryLabel)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                .padding(.top, 8)
                .task(id: item.id) { vault.ensureFavicon(for: item.overview) }

                if let watchtower,
                   let check = watchtower.checks(for: item.id).min(by: { $0.severity < $1.severity }) {
                    warningCard(check)
                }

                let filledSections = item.details.sections.compactMap { section -> (ItemSection, [ItemField])? in
                    let fields = section.fields.filter { !$0.value.isEmpty }
                    return fields.isEmpty ? nil : (section, fields)
                }
                ForEach(Array(filledSections.enumerated()), id: \.offset) { _, pair in
                    let (section, fields) = pair
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.title.isEmpty { SectionHeader(title: section.title) }
                        fieldsCard(fields)
                    }
                }

                if !item.details.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Note")
                        Card { Text(item.details.notes).font(Theme.text(15)).foregroundStyle(Theme.primaryLabel) }
                    }
                }

                if let summary = vault.summaries.first(where: { $0.id == item.id }) {
                    VStack(spacing: 10) {
                        Button {
                            Task { await vault.setArchived(summary, !summary.overview.isArchived); dismiss() }
                        } label: {
                            Label(summary.overview.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                                .font(Theme.text(15, .semibold)).foregroundStyle(Theme.primaryLabel)
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(PressScale())
                        Button {
                            Task { await vault.moveToTrash(summary); dismiss() }
                        } label: {
                            Text("Delete").font(Theme.text(16, .semibold)).foregroundStyle(Theme.accentText)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Theme.danger, in: RoundedRectangle(cornerRadius: Theme.rInput, style: .continuous))
                        }
                        .buttonStyle(PressScale())
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .padding(.bottom, 20)
        }
    }

    private func fieldsCard(_ fields: [ItemField]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.offset) { idx, field in
                IOSFieldRow(field: field, openURL: openURL)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                if idx < fields.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 16) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func warningCard(_ check: WatchtowerCheck) -> some View {
        let color = check.severity == 0 ? Theme.danger : (check.severity == 1 ? Theme.warn : Theme.accent)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(color).padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(check.displayName).font(Theme.text(15, .semibold)).foregroundStyle(color)
                Text(check.explanation).font(Theme.text(13.5)).foregroundStyle(color.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.rBadge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rBadge, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

/// One field row: label + value, tap-to-copy, reveal for secrets, live TOTP, URLs.
private struct IOSFieldRow: View {
    let field: ItemField
    let openURL: OpenURLAction

    @State private var revealed = false
    @State private var copied = false

    private var canReveal: Bool { field.kind == .concealed || field.kind == .sshKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(field.label.uppercased()).font(Theme.caps(11)).tracking(0.5).foregroundStyle(Theme.label)
                Spacer()
                if copied {
                    Label("Copied", systemImage: "checkmark").font(Theme.caps(11)).foregroundStyle(Theme.accent)
                } else {
                    HStack(spacing: 16) {
                        if canReveal {
                            Button { revealed.toggle() } label: {
                                Image(systemName: revealed ? "eye.slash" : "eye").font(.callout)
                            }.buttonStyle(.plain).foregroundStyle(Theme.label)
                        }
                        Image(systemName: "doc.on.doc").font(.callout).foregroundStyle(Theme.label)
                    }
                }
            }
            value
            if field.purpose == .password, !field.value.isEmpty {
                StrengthBar(score: PasswordStrength.score(field.value)).padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { copy() }
    }

    @ViewBuilder private var value: some View {
        switch field.kind {
        case .concealed, .sshKey:
            if revealed {
                Text(coloredSecret(field.value)).font(Theme.mono(15)).textSelection(.enabled)
                    .lineLimit(field.kind == .sshKey ? 8 : 1)
            } else {
                Text(String(repeating: "•", count: min(max(field.value.count, 6), 16))).font(Theme.mono(15))
                    .foregroundStyle(Theme.primaryLabel)
            }
        case .otp:
            TOTPRow(secret: field.value)
        case .url:
            Button { if let url = normalizedURL(field.value) { openURL(url) } } label: {
                Text(field.value).font(Theme.text(16)).foregroundStyle(Theme.accent).lineLimit(1)
            }.buttonStyle(.plain)
        default:
            Text(field.value).font(Theme.text(16)).foregroundStyle(Theme.primaryLabel)
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
                    Text(grouped(code)).font(Theme.mono(20, .semibold)).foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                    Text("\(remaining)s").font(.caption.monospacedDigit())
                        .foregroundStyle(remaining <= 7 ? Theme.warn : Theme.label)
                }
            }
        } else {
            Label("Invalid one-time password", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(Theme.warn)
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
        else if !ch.isLetter { piece.foregroundColor = Theme.danger }
        else { piece.foregroundColor = Theme.primaryLabel }
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
