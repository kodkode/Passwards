import SwiftUI
import TwoPasswordCore

/// The three-pane main window: sidebar · item list · detail.
struct MainWindow: View {
    let appState: AppState
    @State private var store: VaultStore
    @State private var newItemCategoryPickerShown = false
    @State private var generatorShown = false

    init(appState: AppState) {
        self.appState = appState
        _store = State(initialValue: VaultStore(appState: appState))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store, appState: appState)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            ItemListView(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            ItemDetailContainer(store: store)
        }
        .task {
            await store.load()
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
        }
        .sheet(isPresented: $newItemCategoryPickerShown) {
            NewItemCategoryPicker(store: store)
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

/// "+ New Item" category chooser, like 1P8's grid.
struct NewItemCategoryPicker: View {
    let store: VaultStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose a category")
                .font(.title3.bold())
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(TwoPasswordCore.Category.allCases) { category in
                        Button {
                            store.editorDraft = store.newItem(category: category)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                CategoryIconView(category: category, size: 28)
                                Text(category.displayName)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
