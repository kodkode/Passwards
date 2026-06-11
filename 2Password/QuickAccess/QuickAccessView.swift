import SwiftUI
import TwoPasswordCore

/// The Spotlight-style Quick Access content: search row + result rows with
/// keyboard-driven copy actions.
struct QuickAccessView: View {
    let appState: AppState
    let dismiss: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var feedback: String?
    @FocusState private var searchFocused: Bool

    private var store: VaultStore? { appState.vaultStore }

    private var results: [ItemSummary] {
        guard let store, appState.phase == .unlocked else { return [] }
        let active = store.summaries.filter { $0.trashedAt == nil && !$0.overview.isArchived }
        let ranked: [ItemSummary]
        if query.isEmpty {
            ranked = active.sorted {
                ($0.overview.isFavorite ? 0 : 1, $1.updatedAt) < ($1.overview.isFavorite ? 0 : 1, $0.updatedAt)
            }
        } else {
            let q = query.lowercased()
            ranked = active.filter {
                $0.overview.title.lowercased().contains(q)
                || $0.overview.subtitle.lowercased().contains(q)
                || $0.overview.urls.contains { $0.lowercased().contains(q) }
            }.sorted {
                let l0 = $0.overview.title.lowercased().hasPrefix(q) ? 0 : 1
                let l1 = $1.overview.title.lowercased().hasPrefix(q) ? 0 : 1
                return (l0, $0.overview.title) < (l1, $1.overview.title)
            }
        }
        return Array(ranked.prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider().opacity(0.4)
            if appState.phase != .unlocked {
                lockedState
            } else if results.isEmpty {
                Text(query.isEmpty ? "No items yet" : "No results for “\(query)”")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                resultsList
            }
            if let feedback {
                Divider().opacity(0.4)
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(6)
            } else if appState.phase == .unlocked && !results.isEmpty {
                Divider().opacity(0.4)
                hintsRow
            }
        }
        .frame(width: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1))
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            query = ""
            selectedIndex = 0
            searchFocused = true
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, results.count - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            copyPrimary()
            return .handled
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(characters: ["c"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.option) {
                copyOTP()
            } else if press.modifiers.contains(.shift) {
                copyField(.password, label: "Password copied")
            } else {
                copyField(.username, label: "Username copied")
            }
            return .handled
        }
        .onKeyPress(characters: ["o"], phases: .down) { press in
            guard press.modifiers.contains(.command) && press.modifiers.contains(.shift) else { return .ignored }
            openInApp()
            return .handled
        }
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            TextField("Search 2Password…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .onChange(of: query) { selectedIndex = 0 }
        }
        .padding(14)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, summary in
                HStack(spacing: 10) {
                    ItemIconView(summary: summary, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                            .font(.callout.weight(.medium))
                        if !summary.overview.subtitle.isEmpty {
                            Text(summary.overview.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if index == selectedIndex {
                        Text("⏎ copy password")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if summary.overview.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(index == selectedIndex ? Theme.accent.opacity(0.25) : .clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedIndex = index
                    copyPrimary()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var hintsRow: some View {
        HStack(spacing: 14) {
            hint("⏎", "password")
            hint("⌘C", "username")
            hint("⇧⌘C", "password")
            hint("⌥⌘C", "one-time code")
            hint("⇧⌘O", "open")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var lockedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("2Password is locked")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                if appState.biometricUnlockAllowed {
                    Button {
                        Task {
                            if await appState.unlockWithTouchID() {
                                await appState.vaultStore?.reloadFromRemote()
                            }
                        }
                    } label: {
                        Label("Unlock with Touch ID", systemImage: "touchid")
                    }
                }
                Button("Open 2Password") { openInApp() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    // MARK: Actions

    private var selected: ItemSummary? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    private func copyPrimary() {
        copyField(.password, label: "Password copied")
    }

    private func copyField(_ purpose: FieldPurpose, label: String) {
        guard let summary = selected, let store else { return }
        Task {
            guard let item = await store.item(id: summary.id),
                  let field = item.details.firstField(withPurpose: purpose),
                  !field.value.isEmpty else {
                flash("No \(purpose == .username ? "username" : "password") on this item")
                return
            }
            ClipboardManager.copy(field.value, concealed: purpose == .password)
            flash(label)
            try? await Task.sleep(for: .milliseconds(650))
            dismiss()
        }
    }

    private func copyOTP() {
        guard let summary = selected, let store else { return }
        Task {
            guard let item = await store.item(id: summary.id),
                  let field = item.details.firstField(ofKind: .otp),
                  let generator = TOTPGenerator(userInput: field.value) else {
                flash("No one-time password on this item")
                return
            }
            ClipboardManager.copy(generator.code(), concealed: true)
            flash("One-time code copied")
            try? await Task.sleep(for: .milliseconds(650))
            dismiss()
        }
    }

    private func openInApp() {
        if let summary = selected, let store {
            store.selectedItemID = summary.id
            store.sidebarSelection = .allItems
        }
        dismiss()
        NSApp.activate()
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    private func flash(_ message: String) {
        feedback = message
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            feedback = nil
        }
    }
}
