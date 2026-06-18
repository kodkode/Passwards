import SwiftUI
import PasswardsCore

/// The three-pane main window: sidebar · item list · detail.
struct MainWindow: View {
    let appState: AppState
    @State private var store: VaultStore
    @State private var newItemCategoryPickerShown = false
    @State private var generatorShown = false
    @State private var emptyTrashConfirm = false

    init(appState: AppState) {
        self.appState = appState
        _store = State(initialValue: appState.ensureVaultStore())
    }

    var body: some View {
        NavigationSplitView {
            ZStack {
                // Frosted material fills the whole sidebar column FLUSH to the
                // window frame; the List (which macOS 26 insets) floats on top.
                // Putting it here, not as the List's background, avoids the
                // inset "floating card" look and matches 1P8's flush frame.
                SidebarMaterial().ignoresSafeArea()
                SidebarView(store: store, appState: appState)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            ItemListView(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            ItemDetailContainer(store: store)
        }
        .task {
            await store.load()
            appState.sync.onRemoteChanges = { [weak store] in
                Task { await store?.reloadFromRemote() }
            }
            appState.sync.kick()
            await store.watchtower.run()
        }
        .focusedSceneValue(\.vaultStore, store)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newItemCategoryPickerShown = true
                } label: {
                    Label("New Item", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Item (⌘N)")
            }
            ToolbarItem {
                Button {
                    generatorShown = true
                } label: {
                    Label("Password Generator", systemImage: "dice")
                }
                .help("Password Generator")
                .popover(isPresented: $generatorShown, arrowEdge: .bottom) {
                    GeneratorPopover(context: .standalone)
                }
            }
            if store.sidebarSelection == .trash {
                ToolbarItem {
                    Button(role: .destructive) {
                        emptyTrashConfirm = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash")
                    }
                    .help("Empty Recently Deleted")
                }
            }
        }
        .sheet(isPresented: $newItemCategoryPickerShown) {
            NewItemCategoryPicker(store: store)
        }
        .confirmationDialog("Empty Recently Deleted?", isPresented: $emptyTrashConfirm, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) {
                Task { await store.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every item in Recently Deleted. This can’t be undone.")
        }
    }
}

/// Focus plumbing so menu commands can reach the store.
struct VaultStoreKey: FocusedValueKey {
    typealias Value = VaultStore
}

extension FocusedValues {
    var vaultStore: VaultStore? {
        get { self[VaultStoreKey.self] }
        set { self[VaultStoreKey.self] = newValue }
    }
}

/// "+ New Item" chooser, mirroring 1P8's "What would you like to add?" sheet:
/// search, a featured grid of the six everyday categories, then the rest in a
/// two-column list.
struct NewItemCategoryPicker: View {
    let store: VaultStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private static let featured: [PasswardsCore.Category] = [
        .login, .secureNote, .creditCard, .identity, .password, .document,
    ]
    private static let others: [PasswardsCore.Category] = {
        var rest = PasswardsCore.Category.allCases.filter { !featured.contains($0) }
        rest.sort { $0.displayName < $1.displayName }
        // 1P8 leads the secondary list with SSH Key.
        if let index = rest.firstIndex(of: .sshKey) {
            rest.remove(at: index)
            rest.insert(.sshKey, at: 0)
        }
        return rest
    }()

    private func matches(_ category: PasswardsCore.Category) -> Bool {
        query.isEmpty || category.displayName.localizedCaseInsensitiveContains(query)
    }

    private var filteredFeatured: [PasswardsCore.Category] { Self.featured.filter(matches) }
    private var filteredOthers: [PasswardsCore.Category] { Self.others.filter(matches) }

    var body: some View {
        VStack(spacing: 0) {
            Text("What would you like to add?")
                .font(.system(size: 17, weight: .bold))
                .padding(.top, 26)
                .padding(.bottom, 16)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("", text: $query, prompt: Text("Try searching anything"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                    .onSubmit(selectFirstMatch)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
            }
            .padding(.horizontal, 70)
            .padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 0) {
                    if !filteredFeatured.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                            ForEach(filteredFeatured) { category in
                                FeaturedCategoryCard(category: category) { choose(category) }
                            }
                        }
                        if !filteredOthers.isEmpty {
                            Divider()
                                .padding(.vertical, 18)
                        }
                    }
                    if !filteredOthers.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 10) {
                            ForEach(filteredOthers) { category in
                                CompactCategoryRow(category: category) { choose(category) }
                            }
                        }
                    }
                    if filteredFeatured.isEmpty && filteredOthers.isEmpty {
                        Text("No categories match “\(query)”")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 600, height: 620)
        .background(Theme.detailBackground)
        .onExitCommand { dismiss() }
        .onAppear { searchFocused = true }
    }

    private func selectFirstMatch() {
        if let first = filteredFeatured.first ?? filteredOthers.first {
            choose(first)
        }
    }

    private func choose(_ category: PasswardsCore.Category) {
        store.editorDraft = store.newItem(category: category)
        dismiss()
    }
}

/// Large featured card: icon top-left, label bottom-left.
private struct FeaturedCategoryCard: View {
    let category: PasswardsCore.Category
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CategoryIconView(category: category, size: 40)
                Spacer(minLength: 14)
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(hovering ? Color.primary.opacity(0.07) : Theme.fieldCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Compact row: small icon + label, two per line.
private struct CompactCategoryRow: View {
    let category: PasswardsCore.Category
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CategoryIconView(category: category, size: 26)
                Text(category.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(hovering ? Color.primary.opacity(0.07) : Theme.fieldCard, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.fieldCardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
