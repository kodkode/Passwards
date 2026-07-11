import SwiftUI
import PasswardsCore
import PasswardsOrchestration

/// Initials for the header avatar, derived from the account email (fallback "PW").
func accountInitials(_ core: AccountController) -> String {
    guard let email = core.account?.email, let first = email.first else { return "PW" }
    return String(first).uppercased()
}

/// First name for the Home greeting, derived from the account email's local part
/// ("michael.tubul@…" → "Michael"). Handoff: "Hey, Alex!"; fallback "Hey there!".
func accountGreeting(_ core: AccountController) -> String {
    guard let email = core.account?.email,
          let local = email.split(separator: "@").first,
          let name = local.split(whereSeparator: { ".-_+".contains($0) }).first,
          !name.isEmpty, name.allSatisfy({ $0.isLetter })
    else { return "Hey there!" }
    return "Hey, \(name.prefix(1).uppercased() + name.dropFirst().lowercased())!"
}

// MARK: - Home tab

struct IOSHomeTab: View {
    @Bindable var vault: IOSVaultModel
    let watchtower: IOSWatchtowerModel
    var present: (SheetRoute) -> Void
    var selectTab: (IOSTab) -> Void

    @State private var favOpen = true
    @State private var recentOpen = true

    private var active: [ItemSummary] {
        vault.summaries.filter { $0.trashedAt == nil && !$0.overview.isArchived }
    }
    private var favorites: [ItemSummary] { active.filter { $0.overview.isFavorite } }
    private var recent: [ItemSummary] { Array(active.sorted { $0.createdAt > $1.createdAt }.prefix(6)) }

    var body: some View {
        TabScaffold(title: accountGreeting(vault.core), subtitle: "Let's keep things secure",
                    onSettings: { present(.settings) }, onAdd: { present(.add) }) {
            nudgeCard
            promoCard
            favoritesSection
            recentSection
            if active.isEmpty { emptyState }
        }
    }

    private var nudgeCard: some View {
        Button { present(.settings) } label: {
            Card {
                HStack(spacing: 12) {
                    GlossyIcon(symbol: "bolt.fill", color: Theme.warn, size: 40)
                    Text("Unlock at lightning speed — enable Face ID")
                        .font(Theme.text(14, .medium)).foregroundStyle(Theme.primaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("1 step").font(Theme.text(12, .bold)).foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                }
            }
        }
        .buttonStyle(PressScale())
    }

    private var promoCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "globe").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 4) {
                Text("Passwards, now in your browser").font(Theme.title(17, .semibold)).foregroundStyle(.white)
                Text("Autofill, generate, done — browsing just got a lot easier.")
                    .font(Theme.text(13.5)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
    }

    @ViewBuilder private var favoritesSection: some View {
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Favorites", systemImage: "star.fill", collapsible: true,
                              collapsed: !favOpen) { withAnimation(.snappy) { favOpen.toggle() } }
                if favOpen { rowCard(favorites) }
            }
        }
    }

    @ViewBuilder private var recentSection: some View {
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Recently Created", systemImage: "clock.arrow.circlepath",
                              collapsible: true, collapsed: !recentOpen) { withAnimation(.snappy) { recentOpen.toggle() } }
                if recentOpen { rowCard(recent) }
            }
        }
    }

    private func rowCard(_ items: [ItemSummary]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, s in
                ItemRowView(vault: vault, summary: s) { present(.detail(s.id)) }
                if idx < items.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 68) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private var emptyState: some View {
        Card(padding: 28) {
            VStack(spacing: 10) {
                GlossyIcon(symbol: "sparkles", color: Theme.accent, size: 52)
                Text("Nothing here yet").font(Theme.title(18, .semibold)).foregroundStyle(Theme.primaryLabel)
                Text("Tap + to save your first login, card, or note.")
                    .font(Theme.text(14)).foregroundStyle(Theme.label).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Items tab

struct IOSItemsTab: View {
    @Bindable var vault: IOSVaultModel
    var present: (SheetRoute) -> Void

    var body: some View {
        TabScaffold(title: "Your Stuff",
                    onSettings: { present(.settings) }, onAdd: { present(.add) }) {
            Button { present(.collection(.all)) } label: {
                Card {
                    HStack(spacing: 12) {
                        GlossyIcon(symbol: "square.stack.3d.up.fill", color: Theme.accent, size: 40)
                        Text("All Items").font(Theme.text(16, .semibold)).foregroundStyle(Theme.primaryLabel)
                        Spacer()
                        Text("\(vault.activeSummaries.count)").font(Theme.text(15)).foregroundStyle(Theme.label)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.label)
                    }
                }
            }
            .buttonStyle(PressScale())

            section("Vaults") {
                let rows: [(name: String, symbol: String, token: String)] =
                    vault.vaults.isEmpty ? [("Personal", "lock.fill", "slate")]
                                         : vault.vaults.map { ($0.attributes.name, $0.attributes.symbolName, $0.attributes.colorToken) }
                listCard(Array(rows.enumerated()), id: \.offset) { _, v in
                    row(icon: v.symbol, tint: Theme.color(token: v.token), title: v.name, count: nil) { present(.vault(v.name)) }
                }
            }

            let cats = vault.categoryCounts
            if !cats.isEmpty {
                section("Categories") {
                    listCard(Array(cats.enumerated()), id: \.offset) { _, entry in
                        row(icon: entry.category.symbolName, tint: Theme.color(token: entry.category.colorToken),
                            title: entry.category.displayName, count: entry.count) {
                            present(.collection(.category(entry.category)))
                        }
                    }
                }
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title)
            content()
        }
    }

    private func listCard<Data: RandomAccessCollection, ID: Hashable, Row: View>(
        _ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder row: @escaping (Data.Element) -> Row
    ) -> some View {
        VStack(spacing: 0) {
            let items = Array(data)
            ForEach(Array(items.enumerated()), id: \.offset) { idx, el in
                row(el)
                if idx < items.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 62) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
    }

    private func row(icon: String, tint: Color, title: String, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlossyIcon(symbol: icon, color: tint, size: 34)
                Text(title).font(Theme.text(16)).foregroundStyle(Theme.primaryLabel)
                Spacer()
                if let count { Text("\(count)").font(Theme.text(15)).foregroundStyle(Theme.label) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale(scale: 0.98))
    }
}

// MARK: - Sentinel tab

struct IOSSentinelTab: View {
    @Bindable var vault: IOSVaultModel
    let watchtower: IOSWatchtowerModel
    var present: (SheetRoute) -> Void

    var body: some View {
        TabScaffold(title: "Sentinel",
                    onSettings: { present(.settings) }, onAdd: { present(.add) }) {
            VStack(spacing: 16) {
                SentinelGauge(score: watchtower.score, label: watchtower.scoreLabel, size: 232)
                    .frame(maxWidth: .infinity)
                ShareLink(item: "My Passwards security score is \(watchtower.score)/100 — \(watchtower.scoreLabel).") {
                    Card(padding: 13) {
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                            Text("Share My Score").font(Theme.text(15, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(Theme.primaryLabel)
                    }
                }
                .buttonStyle(PressScale())
            }
            .padding(.top, 4)

            Text(watchtower.scoreBody).font(Theme.text(14.5)).foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Overall Password Strength").font(Theme.text(14, .semibold)).foregroundStyle(Theme.primaryLabel)
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.strengthColor(.excellent), Theme.strengthColor(.fair), Theme.strengthColor(.terrible)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 9)
                }
            }

            ForEach(alerts) { alert in
                Button { present(.collection(.flagged(alert.check))) } label: {
                    Card {
                        HStack(alignment: .top, spacing: 12) {
                            GlossyIcon(symbol: alert.icon, color: alert.color, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title).font(Theme.title(16, .semibold)).foregroundStyle(Theme.primaryLabel)
                                Text(alert.body).font(Theme.text(13.5)).foregroundStyle(Theme.label)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.label)
                        }
                    }
                }
                .buttonStyle(PressScale())
            }
        }
        .task { await watchtower.runIfStale() }
    }

    private struct Alert: Identifiable {
        let id = UUID(); let check: WatchtowerCheck; let icon: String; let color: Color
        let title: String; let body: String
    }

    private var alerts: [Alert] {
        var out: [Alert] = []
        if watchtower.compromised > 0 {
            out.append(.init(check: .vulnerablePasswords, icon: "exclamationmark.triangle.fill", color: Theme.danger,
                             title: "\(watchtower.compromised) compromised", body: "Found in known data breaches — change these now."))
        }
        if watchtower.reused > 0 {
            out.append(.init(check: .reusedPasswords, icon: "doc.on.doc.fill", color: Theme.warn,
                             title: "\(watchtower.reused) passwords are reused", body: "The same password protects more than one account."))
        }
        if watchtower.weak > 0 {
            out.append(.init(check: .weakPasswords, icon: "lock.open.fill", color: Theme.accent,
                             title: "\(watchtower.weak) weak passwords", body: "Short or easy to guess — strengthen them."))
        }
        return out
    }
}

// MARK: - Search tab

struct IOSSearchTab: View {
    @Bindable var vault: IOSVaultModel
    var present: (SheetRoute) -> Void

    private var results: [ItemSummary] {
        let q = vault.searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return VaultQuery.filteredSorted(vault.summaries, filter: .allItems, search: q,
                                         categoryFilter: nil, sortKey: .title, ascending: true)
    }

    var body: some View {
        TabScaffold(title: "Search",
                    onSettings: { present(.settings) }, onAdd: { present(.add) }) {
            Card(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.label)
                    TextField("Search your items", text: $vault.searchText)
                        .font(Theme.text(15.5)).foregroundStyle(Theme.primaryLabel)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !vault.searchText.isEmpty {
                        Button { vault.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.label)
                        }.buttonStyle(.plain)
                    }
                }
            }

            if vault.searchText.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Theme.accent.opacity(0.55))
                    Text("Search your logins, cards, notes\u{2009}—\u{2009}anything you've saved.")
                        .font(Theme.text(14)).foregroundStyle(Theme.label)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 24)
            } else {
                if results.isEmpty {
                    Text("No items match your search").font(Theme.text(14)).foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { idx, s in
                            ItemRowView(vault: vault, summary: s) { present(.detail(s.id)) }
                            if idx < results.count - 1 { Divider().overlay(Theme.cardBorder).padding(.leading, 68) }
                        }
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
                }
            }
        }
    }
}
