import SwiftUI
import TwoPasswordCore

struct SidebarView: View {
    @Bindable var store: VaultStore
    let appState: AppState
    @State private var newVaultShown = false

    var body: some View {
        List(selection: $store.sidebarSelection) {
            accountHeader
                .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 10, trailing: 8))

            Label("All Items", systemImage: "square.grid.2x2")
                .tag(SidebarFilter.allItems)
            Label("Favorites", systemImage: "star")
                .tag(SidebarFilter.favorites)
            Label("Watchtower", systemImage: "shield.lefthalf.filled")
                .tag(SidebarFilter.watchtower)

            Section("Vaults") {
                ForEach(store.vaults) { vault in
                    Label {
                        Text(vault.attributes.name)
                    } icon: {
                        Image(systemName: vault.attributes.symbolName)
                            .foregroundStyle(Theme.color(token: vault.attributes.colorToken))
                    }
                    .tag(SidebarFilter.vault(vault.id))
                }
                Button {
                    newVaultShown = true
                } label: {
                    Label("New Vault…", systemImage: "plus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Section("Categories") {
                ForEach(TwoPasswordCore.Category.allCases) { category in
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
                            CategoryIconView(category: category, size: 18)
                        }
                        .tag(SidebarFilter.category(category))
                    }
                }
            }

            if !store.allTags.isEmpty {
                Section("Tags") {
                    ForEach(store.allTags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(SidebarFilter.tag(tag))
                    }
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
        .sheet(isPresented: $newVaultShown) {
            NewVaultSheet(store: store)
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
                .help("Lock 2Password (⇧⌘L)")
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

    private func categoryCount(_ category: TwoPasswordCore.Category) -> Int {
        store.summaries.lazy.filter {
            $0.trashedAt == nil && !$0.overview.isArchived && $0.overview.category == category
        }.count
    }

    private var accountHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent.gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Text(initials)
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Personal")
                    .font(.callout.weight(.semibold))
                Text(appState.account?.email ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var initials: String {
        let email = appState.account?.email ?? "?"
        return String(email.prefix(2)).uppercased()
    }
}

struct NewVaultSheet: View {
    let store: VaultStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbolName = "lock.fill"
    @State private var colorToken = "blue"

    private let symbols = ["lock.fill", "person.fill", "briefcase.fill", "house.fill", "creditcard.fill", "airplane", "heart.fill", "star.fill", "folder.fill", "graduationcap.fill"]
    private let colors = ["blue", "teal", "green", "orange", "red", "purple", "pink", "steel"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Vault").font(.title3.bold())
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
                Button("Create") {
                    Task {
                        await store.createVault(name: name, symbolName: symbolName, colorToken: colorToken)
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
