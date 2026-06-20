import SwiftUI

/// The in-app Help window: a multi-article library rendered from the bundled
/// `PasswardsHelp.md`. That single Markdown file is also the source uploaded to
/// the website, so the help content is written once. Articles are separated by
/// top-level `#` headings and grouped in the sidebar via `<!-- GROUP: Name -->`
/// marker comments (which stay invisible when the same file renders on the web).
struct HelpView: View {
    @State private var groups: [HelpMarkdown.Group] = []
    @State private var selection: String?
    @State private var loadFailed = false

    private var selectedArticle: HelpMarkdown.Article? {
        guard let selection else { return nil }
        for group in groups {
            if let article = group.articles.first(where: { $0.id == selection }) { return article }
        }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.articles) { article in
                            Text(article.title)
                                .font(.callout)
                                .lineLimit(2)
                                .tag(article.id)
                        }
                    }
                }
            }
            .navigationTitle("Help")
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                if let article = selectedArticle {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text(article.title)
                            .font(.largeTitle.bold())
                            .padding(.bottom, 4)
                        ForEach(article.blocks) { item in
                            HelpBlockView(block: item.block)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(article.id) // reset scroll position when switching articles
                } else if loadFailed {
                    Text("Help content couldn't be loaded.")
                        .foregroundStyle(.secondary)
                        .padding(28)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear(perform: load)
    }

    private func load() {
        guard groups.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "PasswardsHelp", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            loadFailed = true
            return
        }
        groups = HelpMarkdown.parseLibrary(text)
        selection = groups.first?.articles.first?.id
    }
}

/// Renders a single parsed Markdown block as native SwiftUI.
private struct HelpBlockView: View {
    let block: HelpMarkdown.Block

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(text)
                .font(level == 2 ? .title2.bold() : .title3.weight(.semibold))
                .padding(.top, level == 2 ? 12 : 6)
        case let .paragraph(text):
            Text(text).font(.body)
        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(text).font(.body)
            }
            .padding(.leading, 6)
        case let .numbered(number, text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).").foregroundStyle(.secondary).monospacedDigit()
                Text(text).font(.body)
            }
            .padding(.leading, 6)
        case let .code(text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case let .callout(text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
                Text(text).font(.callout)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .divider:
            Divider().padding(.vertical, 6)
        case let .table(headers, rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                        Text(h).font(.callout.bold())
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(cell).font(.callout)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A small Markdown parser covering the subset used by the Passwards help file:
/// a library of articles (split on `#` headings, grouped by `<!-- GROUP: -->`),
/// each with headings, paragraphs, bullet/numbered lists, code blocks,
/// blockquote callouts, horizontal rules, and simple tables. Inline styling
/// (**bold**, *italic*, `code`, links) is handled by `AttributedString`.
enum HelpMarkdown {
    enum Block {
        case heading(level: Int, text: String)
        case paragraph(AttributedString)
        case bullet(AttributedString)
        case numbered(number: Int, text: AttributedString)
        case code(String)
        case callout(AttributedString)
        case divider
        case table(headers: [AttributedString], rows: [[AttributedString]])
    }

    struct Item: Identifiable {
        let id: Int
        let block: Block
    }

    struct Article: Identifiable {
        let id: String     // slug, unique within the library
        let title: String
        let blocks: [Item]
    }

    struct Group: Identifiable {
        let name: String
        var articles: [Article]
        var id: String { name }
    }

    /// Splits the combined help file into grouped articles.
    static func parseLibrary(_ text: String) -> [Group] {
        let lines = text.components(separatedBy: "\n")
        var groups: [Group] = []
        var currentGroup = "Help"
        var currentTitle: String?
        var body: [String] = []
        var usedSlugs = Set<String>()

        func finishArticle() {
            guard let title = currentTitle else { body.removeAll(); return }
            var slug = slugify(title)
            var n = 2
            while usedSlugs.contains(slug) { slug = "\(slugify(title))-\(n)"; n += 1 }
            usedSlugs.insert(slug)
            let article = Article(id: slug, title: title, blocks: parseBlocks(body))
            if let idx = groups.firstIndex(where: { $0.name == currentGroup }) {
                groups[idx].articles.append(article)
            } else {
                groups.append(Group(name: currentGroup, articles: [article]))
            }
            currentTitle = nil
            body.removeAll()
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let group = groupMarker(line) {
                finishArticle()
                currentGroup = group
                continue
            }
            if line.hasPrefix("# ") {
                finishArticle()
                currentTitle = String(line.dropFirst(2))
                continue
            }
            if currentTitle != nil { body.append(raw) }
        }
        finishArticle()
        return groups
    }

    /// Parses the body lines of one article into renderable blocks.
    static func parseBlocks(_ lines: [String]) -> [Item] {
        var blocks: [Block] = []
        var i = 0
        var paragraph: [String] = []
        var callout: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraph.joined(separator: " "))))
            paragraph.removeAll()
        }
        func flushCallout() {
            guard !callout.isEmpty else { return }
            blocks.append(.callout(inline(callout.joined(separator: " "))))
            callout.removeAll()
        }
        func flushAll() { flushParagraph(); flushCallout() }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.isEmpty { flushAll(); i += 1; continue }

            if line.hasPrefix("```") {
                flushAll()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if line == "---" || line == "***" {
                flushAll(); blocks.append(.divider); i += 1; continue
            }

            if line.hasPrefix("|") {
                flushAll()
                var tableLines: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[i].trimmingCharacters(in: .whitespaces)); i += 1
                }
                if let table = parseTable(tableLines) { blocks.append(table) }
                continue
            }

            if line.hasPrefix(">") {
                flushParagraph()
                callout.append(String(line.dropFirst().trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            } else {
                flushCallout()
            }

            if line.hasPrefix("### ") {
                flushAll(); blocks.append(.heading(level: 3, text: String(line.dropFirst(4)))); i += 1; continue
            }
            if line.hasPrefix("## ") {
                flushAll(); blocks.append(.heading(level: 2, text: String(line.dropFirst(3)))); i += 1; continue
            }
            if line.hasPrefix("# ") {
                // A stray H1 inside a body; treat as a section heading.
                flushAll(); blocks.append(.heading(level: 2, text: String(line.dropFirst(2)))); i += 1; continue
            }

            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph(); blocks.append(.bullet(inline(String(line.dropFirst(2))))); i += 1; continue
            }

            if let match = numberedPrefix(line) {
                flushParagraph(); blocks.append(.numbered(number: match.number, text: inline(match.rest))); i += 1; continue
            }

            paragraph.append(line)
            i += 1
        }
        flushAll()
        return blocks.enumerated().map { Item(id: $0.offset, block: $0.element) }
    }

    // MARK: Helpers

    private static func groupMarker(_ line: String) -> String? {
        guard line.hasPrefix("<!--"), line.contains("GROUP:"), line.hasSuffix("-->") else { return nil }
        guard let range = line.range(of: "GROUP:") else { return nil }
        let after = line[range.upperBound...].replacingOccurrences(of: "-->", with: "")
        return after.trimmingCharacters(in: .whitespaces)
    }

    private static func inline(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(string)
    }

    private static func numberedPrefix(_ line: String) -> (number: Int, rest: String)? {
        guard let dot = line.firstIndex(of: "."),
              line.index(after: dot) < line.endIndex,
              line[line.index(after: dot)] == " " else { return nil }
        guard let number = Int(line[line.startIndex..<dot]) else { return nil }
        let rest = String(line[line.index(dot, offsetBy: 2)...])
        return (number, rest)
    }

    private static func parseTable(_ lines: [String]) -> Block? {
        func cells(_ line: String) -> [String] {
            var trimmed = line
            if trimmed.hasPrefix("|") { trimmed.removeFirst() }
            if trimmed.hasSuffix("|") { trimmed.removeLast() }
            return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard lines.count >= 2 else { return nil }
        let headers = cells(lines[0]).map(inline)
        let rows = lines.dropFirst(2).map { cells($0).map(inline) }
        return .table(headers: headers, rows: Array(rows))
    }

    private static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let mapped = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            if ch == " " || ch == "-" { return "-" }
            return "\u{0}"
        }
        return String(mapped).replacingOccurrences(of: "\u{0}", with: "")
            .replacingOccurrences(of: "--", with: "-")
    }
}
