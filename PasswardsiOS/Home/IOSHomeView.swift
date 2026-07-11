import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// The four main tabs (playful design). Generator is not a tab — generation lives
/// in the editor; Settings is a sheet, not a tab.
enum IOSTab: Hashable { case home, items, sentinel, search }

/// A modal bottom sheet the shell can present.
enum SheetRoute: Identifiable, Hashable {
    case add
    case settings
    case detail(String)                 // item id
    case collection(CollectionKind)
    case vault(String)                  // vault name
    var id: String {
        switch self {
        case .add: "add"; case .settings: "settings"
        case .detail(let i): "detail-\(i)"
        case .collection(let k): "collection-\(k.title)"
        case .vault(let v): "vault-\(v)"
        }
    }
}

/// What a Collection sheet lists.
enum CollectionKind: Hashable {
    case all, favorites, recent, archive, trash
    case category(PasswardsCore.Category)
    case vault(String)
    case tag(String)
    case flagged(WatchtowerCheck)       // Sentinel alert drill-down

    var title: String {
        switch self {
        case .all: "All Items"; case .favorites: "Favorites"; case .recent: "Recently Created"
        case .archive: "Archive"; case .trash: "Trash"
        case .category(let c): c.displayName
        case .vault(let v): v
        case .tag(let t): t
        case .flagged(let c): c.displayName
        }
    }
}

/// The unlocked shell: a full-bleed tab content area under a floating pill tab bar,
/// with modal bottom sheets. Loads the vault + runs Watchtower on appear.
struct IOSHomeView: View {
    @Bindable var vault: IOSVaultModel
    let watchtower: IOSWatchtowerModel
    private var core: AccountController { vault.core }

    @State private var tab: IOSTab = .home
    @State private var sheet: SheetRoute?
    @AppStorage(IOSAppearance.storageKey) private var appearanceRaw = IOSAppearance.system.rawValue
    private var appearance: IOSAppearance { IOSAppearance(rawValue: appearanceRaw) ?? .system }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            Group {
                switch tab {
                case .home: IOSHomeTab(vault: vault, watchtower: watchtower, present: present, selectTab: { tab = $0 })
                case .items: IOSItemsTab(vault: vault, present: present)
                case .sentinel: IOSSentinelTab(vault: vault, watchtower: watchtower, present: present)
                case .search: IOSSearchTab(vault: vault, present: present)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabPill(tab: $tab)
        }
        .sheet(item: $sheet) { route in
            // Sheets are a separate presentation context, so the root's
            // preferredColorScheme doesn't reach an already-open sheet — apply it
            // here too so the Appearance toggle re-themes the open Settings sheet live.
            sheetContent(route).preferredColorScheme(appearance.colorScheme)
        }
        .task {
            await vault.load()
            core.sync.onRemoteChanges = { [weak vault, weak watchtower] in
                Task { await vault?.load(); await watchtower?.run() }
            }
            core.sync.kick()
            await watchtower.run()
        }
    }

    private func present(_ route: SheetRoute) { sheet = route }

    @ViewBuilder private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .add:
            IOSAddSheet(vault: vault)
        case .settings:
            IOSSettingsSheet(vault: vault)
        case .detail(let id):
            NavigationStack {
                IOSItemDetailView(vault: vault, itemID: id, watchtower: watchtower)
            }
            .presentationCornerRadius(Theme.rSheet)
        case .collection(let kind):
            IOSCollectionSheet(vault: vault, kind: kind, watchtower: watchtower)
        case .vault(let name):
            IOSVaultSheet(vault: vault, vaultName: name)
        }
    }
}

// MARK: - Shared header (shown atop every tab)

/// The row shared across all four tabs: tappable avatar + chevron (→ Settings) on
/// the left, a circular "+" (→ Add) on the right.
struct AppHeader: View {
    var initials: String = "AR"
    var onSettings: () -> Void
    var onAdd: () -> Void

    var body: some View {
        HStack {
            Button(action: onSettings) {
                HStack(spacing: 7) {
                    Avatar(initials: initials, size: 40)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.label)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.primaryLabel)
                    .frame(width: 40, height: 40)
                    .background(Theme.surfaceHigh, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A tab's scaffold: the shared header, a large Fredoka title (+ optional subtitle),
/// then scrolling content. Applies the playful screen padding.
struct TabScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var onSettings: () -> Void
    var onAdd: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AppHeader(onSettings: onSettings, onAdd: onAdd)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(30, .semibold)).tracking(-0.5)
                        .foregroundStyle(Theme.primaryLabel)
                    if let subtitle {
                        Text(subtitle).font(Theme.text(15)).foregroundStyle(Theme.label)
                    }
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Floating pill tab bar

private struct TabPill: View {
    @Binding var tab: IOSTab
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.rTab, style: .continuous) }

    var body: some View {
        bar
            .modifier(TabBarGlass(shape: shape))
            // Improved ambient shadow for depth + a tighter contact shadow
            .shadow(color: .black.opacity(0.15), radius: 28, y: 12)
            .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
    }

    private var bar: some View {
        HStack(spacing: 4) {
            item(.home, "house.fill", "Home")
            item(.items, "square.stack.fill", "Items")
            item(.sentinel, "shield.lefthalf.filled", "Sentinel")
            item(.search, "magnifyingglass", "Search")
        }
        .padding(6)
        // Animate the active tab background pill movement without animating the full screen transition
        .animation(.snappy(duration: 0.2), value: tab)
    }

    private func item(_ t: IOSTab, _ icon: String, _ label: String) -> some View {
        let active = tab == t
        return Button {
            tab = t
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold))
                Text(label).font(Theme.text(10.5, .semibold))
            }
            .foregroundStyle(active ? Theme.accent : Theme.label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle()) // Ensures the clear background area remains tappable
            .background(active ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale(scale: 0.92))
    }
}

/// Native Apple **Liquid Glass** for the floating tab bar on iOS 26; a clean
/// translucent material on iOS 18–25.
private struct TabBarGlass: ViewModifier {
    let shape: RoundedRectangle
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.cardBorder.opacity(0.5), lineWidth: 0.5))
                .clipShape(shape)
        }
    }
}

/// Press feedback used across playful tappable cards/buttons.
struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Shared card + row building blocks

/// A big rounded surface card (28px radius, hairline border).
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}

/// A tappable item row: glossy/favicon icon, title, subtitle, and (optional) chevron.
struct ItemRowView: View {
    let vault: IOSVaultModel
    let summary: ItemSummary
    var showChevron = false
    var onTap: () -> Void

    var body: some View {
        // Favicons are resolved into IOSVaultModel (the @Observable the tabs already
        // observe to draw these rows) and handed to ItemIcon as a plain UIImage value.
        // The leaf holds no @State/.task/UIViewRepresentable, so Home's re-render churn
        // and the same item appearing in Favorites AND Recent can't strand it.
        HStack(spacing: 12) {
            ItemIcon(overview: summary.overview, favicon: vault.favicon(for: summary.overview), size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.overview.title.isEmpty ? "Untitled" : summary.overview.title)
                    .font(Theme.text(15, .semibold)).foregroundStyle(Theme.primaryLabel).lineLimit(1)
                if !summary.overview.subtitle.isEmpty {
                    Text(summary.overview.subtitle).font(Theme.text(12.5)).foregroundStyle(Theme.label).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if summary.overview.isFavorite {
                Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Theme.warn)
            }
            if showChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// A section header: uppercase DM Sans, with an optional trailing chevron for
/// collapsible sections.
struct SectionHeader: View {
    let title: String
    var systemImage: String?
    var collapsible = false
    var collapsed = false
    var onToggle: (() -> Void)?

    var body: some View {
        Button {
            onToggle?()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.label)
                }
                Text(title.uppercased()).font(Theme.caps(12.5, .bold)).tracking(0.5).foregroundStyle(Theme.label)
                Spacer()
                if collapsible {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.label)
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!collapsible)
    }
}
