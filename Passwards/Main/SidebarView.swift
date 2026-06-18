import SwiftUI
import AppKit
import PasswardsCore

/// The native frosted sidebar material (behind-window vibrancy). SwiftUI's bare
/// `.listStyle(.sidebar)` doesn't reliably render it on every macOS build, so we
/// back the sidebar list with this explicitly. Requires the window to be
/// non-opaque (see `WindowConfigurator`) for `.behindWindow` to reveal the
/// desktop — exactly the material 1Password 8, Finder, and Mail use.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct SidebarView: View {
    @Bindable var store: VaultStore
    let appState: AppState
    @State private var newVaultShown = false
    @State private var editingVault: Vault?

    var body: some View {
        List(selection: $store.sidebarSelection) {
            accountHeader
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))

            Label("All Items", systemImage: "square.grid.2x2")
                .tag(SidebarFilter.allItems)
            Label("Favorites", systemImage: "star")
                .tag(SidebarFilter.favorites)
            Label {
                HStack {
                    Text("Watchtower")
                    if store.watchtower.report.totalIssues > 0 {
                        Spacer()
                        Text("\(store.watchtower.report.totalIssues)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.9), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
            .tag(SidebarFilter.watchtower)

            Section {
                ForEach(store.vaults) { vault in
                    Label {
                        Text(vault.attributes.name)
                    } icon: {
                        Image(systemName: vault.attributes.symbolName)
                            .foregroundStyle(Theme.color(token: vault.attributes.colorToken))
                    }
                    .tag(SidebarFilter.vault(vault.id))
                    .contextMenu {
                        Button("Edit Vault…") { editingVault = vault }
                    }
                }
            } header: {
                HStack {
                    Text("VAULTS")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Button {
                        newVaultShown = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("New Vault")
                }
            }

            Section {
                ForEach(PasswardsCore.Category.allCases) { category in
                    if categoryCount(category) > 0 {
                        Label {
                            HStack {
                                Text(category.displayName)
                                Spacer()
                                Text("\(categoryCount(category))")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        } icon: {
                            CategoryIconView(category: category, size: 16)
                        }
                        .tag(SidebarFilter.category(category))
                    }
                }
            } header: {
                Text("CATEGORIES")
                    .font(.system(size: 11, weight: .semibold))
            }

            if !store.allTags.isEmpty {
                Section {
                    ForEach(store.allTags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarFilter.tag(tag))
                    }
                } header: {
                    Text("TAGS")
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            Section {
                Label("Archive", systemImage: "archivebox")
                    .tag(SidebarFilter.archive)
                Label {
                    HStack {
                        Text("Recently Deleted")
                        if store.trashCount > 0 {
                            Spacer()
                            Text("\(store.trashCount)")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: "trash")
                }
                .tag(SidebarFilter.trash)
            }
        }
        .listStyle(.sidebar)
        // Transparent so the window-level frosted material (see MainWindow)
        // shows through FLUSH to the window frame — not as an inset card.
        .scrollContentBackground(.hidden)
        .font(.system(size: 14.5))
        .environment(\.defaultMinListRowHeight, 40)
        .sheet(isPresented: $newVaultShown) {
            NewVaultSheet(store: store)
        }
        .sheet(item: $editingVault) { vault in
            NewVaultSheet(store: store, vault: vault)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    appState.lock()
                } label: {
                    Label("Lock", systemImage: "lock.fill")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Lock Passwards (⇧⌘L)")
                Spacer()
                syncIndicator
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private var syncIndicator: some View {
        switch appState.sync.status {
        case .disabled:
            EmptyView()
        case .idle:
            Image(systemName: "checkmark.icloud")
                .foregroundStyle(.secondary)
                .help("Synced with iCloud")
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .help("Syncing…")
        case .error(let message):
            Image(systemName: "exclamationmark.icloud")
                .foregroundStyle(.orange)
                .help("Sync error: \(message)")
        case .accountUnavailable:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.secondary)
                .help("iCloud account unavailable")
        }
    }

    private func categoryCount(_ category: PasswardsCore.Category) -> Int {
        store.summaries.lazy.filter {
            $0.trashedAt == nil && !$0.overview.isArchived && $0.overview.category == category
        }.count
    }

    private var accountHeader: some View {
        HStack(spacing: 10) {
            DefaultAvatarView(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Personal")
                    .font(.system(size: 14, weight: .semibold))
                Text(appState.account?.email ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct NewVaultSheet: View {
    let store: VaultStore
    /// nil = create a new vault; non-nil = edit this existing vault.
    var vault: Vault?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbolName: String
    @State private var colorToken: String

    init(store: VaultStore, vault: Vault? = nil) {
        self.store = store
        self.vault = vault
        _name = State(initialValue: vault?.attributes.name ?? "")
        _symbolName = State(initialValue: vault?.attributes.symbolName ?? "lock.fill")
        _colorToken = State(initialValue: vault?.attributes.colorToken ?? "blue")
    }

    private let symbols = ["lock.fill", "person.fill", "briefcase.fill", "house.fill", "creditcard.fill", "airplane", "heart.fill", "star.fill", "folder.fill", "graduationcap.fill"]
    private let colors = ["blue", "teal", "green", "orange", "red", "purple", "pink", "steel"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vault == nil ? "New Vault" : "Edit Vault").font(.title3.bold())
            TextField("Name", text: $name, prompt: Text("Vault name"))
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .frame(width: 28, height: 28)
                            .background(
                                symbolName == symbol ? Theme.accent.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                ForEach(colors, id: \.self) { token in
                    Button {
                        colorToken = token
                    } label: {
                        Circle()
                            .fill(Theme.color(token: token))
                            .frame(width: 20, height: 20)
                            .overlay {
                                if colorToken == token {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(vault == nil ? "Create" : "Save") {
                    Task {
                        if let vault {
                            await store.updateVault(vaultID: vault.id, name: name, symbolName: symbolName, colorToken: colorToken)
                        } else {
                            await store.createVault(name: name, symbolName: symbolName, colorToken: colorToken)
                        }
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
