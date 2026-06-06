import SwiftUI
import AppKit

// MARK: - Paper Detail View

struct PaperDetailView: View {
    let paper: Paper
    private var metadata: MetadataStore { .shared }
    @Binding var isTranslating: Bool
    @Binding var isResolvingPdf: Bool

    let onTranslate: (Paper) -> Void
    let onResolvePdf: (Paper) -> Void
    let onStatusChange: (Paper, PaperStatus) -> Void
    let onAddTag: (Paper, String) -> Void
    let onRemoveTag: (Paper, String) -> Void
    let onAddToCollection: (Paper, String) -> Void
    let onRemoveFromCollection: (Paper, String) -> Void
    /// Incremented by the Add Tag keyboard command to open the tag prompt.
    let addTagSignal: Int

    @FocusState private var noteFocused: Bool
    @State private var showCollectionPopover = false
    @State private var showingTranslation: Bool = false
    @State private var lastPersistedNote: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // MARK: Header Card
                headerCard

                Divider().padding(.horizontal, 20)

                // MARK: Tags
                tagSection

                Divider().padding(.horizontal, 20)

                // MARK: Abstract
                abstractSection

                // MARK: Notes
                notesSection

                // MARK: System Memo
                systemMemoSection

                Divider().padding(.horizontal, 20)

                // MARK: Related Papers (lazy — fetched only when scrolled into view)
                RelatedPapersSection(workId: paper.id)
            }
            .padding(.vertical, 16)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onChange(of: addTagSignal) { _, _ in presentAddTagPrompt() }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title — max 3 lines; full title via tooltip
            Text(paper.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .lineSpacing(3)
                .lineLimit(3)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .help(paper.title)

            // Authors
            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }

            metaCard
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var pdfButton: some View {
        Button {
            onResolvePdf(paper)
        } label: {
            Group {
                if isResolvingPdf {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: pdfButtonIcon)
                }
            }
            .detailActionChrome()
        }
        .buttonStyle(.plain)
        .disabled(isResolvingPdf)
        .help(pdfButtonHelp)
    }

    /// Reflects the PDF lifecycle: a downloaded paper reads offline, an
    /// invalid/missing one warns, and an unfetched one offers to fetch.
    private var pdfButtonIcon: String {
        switch PdfStatus(rawValue: paper.pdfStatus ?? "") {
        case .downloaded:     return "doc.text"
        case .notPdf, .dead:  return "exclamationmark.triangle"
        default:              return "doc.text.magnifyingglass"
        }
    }

    private var pdfButtonHelp: String {
        switch PdfStatus(rawValue: paper.pdfStatus ?? "") {
        case .downloaded:     return L10n.t(.openPDF)
        case .notPdf, .dead:  return L10n.pick("No PDF available — retry fetch", "无可用 PDF — 重试获取")
        default:              return L10n.pick("Fetch PDF", "获取 PDF")
        }
    }

    private var citeButton: some View {
        Button {
            copyToPasteboard(CitationExporter.bibtex(for: paper))
            NotificationCenter.shared.showToast(L10n.t(.copiedBibtex), type: .success)
        } label: {
            Image(systemName: "text.quote").detailActionChrome()
        }
        .buttonStyle(.plain)
        .help(L10n.t(.cite))
    }

    private func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private var collectionButton: some View {
        let isInAny = !paper.collectionIds.isEmpty
        return Button {
            showCollectionPopover = true
        } label: {
            Image(systemName: isInAny ? "folder.fill" : "folder").detailActionChrome()
        }
        .buttonStyle(.plain)
        .help(L10n.pick("Manage collections", "管理 Collection"))
        .popover(isPresented: $showCollectionPopover, arrowEdge: .bottom) {
            CollectionPickerPopover(
                paper: paper,
                onAddToCollection: onAddToCollection,
                onRemoveFromCollection: onRemoveFromCollection
            )
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Venue | Score | Citations | Date | Topics | … | 📁 📄
            HStack(spacing: 6) {
                if !paper.venueAbbr.isEmpty {
                    TagChip.venue(
                        paper.venueAbbr,
                        color: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                        size: .regular
                    )
                    .help(venueDisplayName.isEmpty ? paper.venueAbbr : venueDisplayName)
                }

                TagChip.score(paper.score, color: metadata.tierColor(paper.tier), size: .regular)
                    .help(scoreHelp)

                TagChip.citations(paper.citedByCount, size: .regular)
                    .help(citationHelp)

                if !paper.publicationDate.isEmpty {
                    TagChip.date(paper.publicationDate, size: .regular)
                        .help(L10n.pick("Published \(paper.publicationDate)", "发表于 \(paper.publicationDate)"))
                }

                if !topics.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(topics, id: \.self) { topic in
                            TagChip(text: topic, color: metadata.topicColor(topic), size: .regular)
                                .help(topic)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    citeButton
                    collectionButton
                    pdfButton
                }
            }

            // Row 2: Full venue name
            if !venueDisplayName.isEmpty {
                DetailVenueLine(value: venueDisplayName)
                    .help(venueDisplayName)
            }

            if !doiDisplay.isEmpty {
                DetailExternalLinkLine(label: "LINK", value: doiDisplay, url: doiUrl)
            } else if !landingPageDisplay.isEmpty {
                DetailExternalLinkLine(label: "LINK", value: landingPageDisplay, url: landingPageUrl)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.16), lineWidth: 0.5)
        )
    }

    private var scoreHelp: String {
        let score = String(format: "%.0f", paper.score)
        return L10n.pick("Score \(score)  ·  Tier \(paper.tier)", "评分 \(score)  ·  等级 \(paper.tier)")
    }

    private var citationHelp: String {
        let n = paper.citedByCount
        return L10n.pick("\(n) citation\(n == 1 ? "" : "s")", "被引用 \(n) 次")
    }

    private var doiDisplay: String {
        guard let doi = paper.doi, !doi.isEmpty else { return "" }
        return doi
    }

    private var doiUrl: URL? {
        guard let doi = paper.doi, !doi.isEmpty else { return nil }
        if let url = URL(string: doi), url.scheme != nil {
            return url
        }
        return URL(string: "https://doi.org/\(doi)")
    }

    private var landingPageDisplay: String {
        let value = paper.landingPageUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "" : value
    }

    private var landingPageUrl: URL? {
        guard !landingPageDisplay.isEmpty else { return nil }
        return URL(string: landingPageDisplay)
    }

    private var venueDisplayName: String {
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty { return venue }

        let abbr = paper.venueAbbr.trimmingCharacters(in: .whitespacesAndNewlines)
        return abbr == "Others" ? "" : abbr
    }

    private var topics: [String] {
        // Archived topics stay on the paper but their label is hidden.
        metadata.visibleTopicNames(in: paper.track)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader(icon: "tag", title: "Tags")
                Spacer()
                Button {
                    presentAddTagPrompt()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Tag")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.pick("Add a tag to this paper", "为这篇论文添加标签"))
            }

            if paper.tags.isEmpty {
                Text("No tags yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(paper.tags, id: \.self) { tag in
                        PaperTagChip(title: "#\(tag)")
                            .help(L10n.pick("Right-click to remove this tag", "右键以移除此标签"))
                            .contextMenu {
                                Button("Remove Tag") {
                                    onRemoveTag(paper, tag)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func presentAddTagPrompt() {
        NotificationCenter.shared.present(AlertItem(
            title: L10n.t(.cmdAddTag),
            message: nil,
            actions: [
                .confirm("Add", action: {
                    let tag = NotificationCenter.shared.currentAlert?.textFieldValue ?? ""
                    self.onAddTag(self.paper, tag)
                }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: "",
            textFieldLabel: "Tag"
        ))
    }

    // MARK: - Abstract Section

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(icon: "text.alignleft", title: "Abstract")
                Spacer()
                if isTranslating {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Translating...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !paper.abstractZh.isEmpty {
                    Button {
                        showingTranslation.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                            Text(showingTranslation ? "Original" : "Translation")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(showingTranslation
                          ? L10n.pick("Switch to original abstract", "切换到原文摘要")
                          : L10n.pick("Show translated abstract", "显示译文摘要"))
                } else if !paper.abstract.isEmpty {
                    Button {
                        onTranslate(paper)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Translate")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.pick("Translate abstract via AI", "通过 AI 翻译摘要"))
                }
            }

            if showingTranslation && !paper.abstractZh.isEmpty {
                Text(paper.abstractZh)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(.primary)
            } else {
                Text(paper.abstract.isEmpty ? "No abstract available." : paper.abstract)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(4)
                    .foregroundStyle(paper.abstract.isEmpty ? .secondary : .primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .onChange(of: paper.id) { _, _ in
            showingTranslation = false
            lastPersistedNote = paper.note
        }
        .onChange(of: isTranslating) { _, translating in
            if !translating, !paper.abstractZh.isEmpty {
                showingTranslation = true
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "square.and.pencil", title: "Notes")

            TextEditor(text: Binding(
                get: { paper.note },
                set: { newValue in
                    paper.note = newValue
                }
            ))
            .focused($noteFocused)
            .font(.system(size: 13))
            .lineSpacing(3)
            .frame(minHeight: 120, maxHeight: .infinity)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(noteFocused ? 0.4 : 0.2), lineWidth: 1)
            )
            .onChange(of: noteFocused) {
                if !noteFocused {
                    saveNoteIfChanged()
                }
            }
            .onAppear {
                lastPersistedNote = paper.note
            }
            .onDisappear {
                saveNoteIfChanged()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func saveNoteIfChanged() {
        guard paper.note != lastPersistedNote else { return }
        PaperStore.shared.setPaperNote(id: paper.id, note: paper.note)
        lastPersistedNote = paper.note
    }

    private var systemMemoSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(icon: "sparkles", title: "Memo")

            VStack(alignment: .leading, spacing: 7) {
                MemoLine(title: "Recommendation", value: recommendationMemo)
                MemoLine(title: "Venue Rule", value: venueRuleMemo)
                MemoLine(title: "Score", value: scoreMemo)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var recommendationMemo: String {
        let reason = paper.recommendationReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if paper.isRecommended { return reason.isEmpty ? "Active recommendation" : reason }
        return "Not currently recommended"
    }

    private var venueRuleMemo: String {
        guard let rule = matchedVenueRule else {
            let field = metadata.field(forAbbr: paper.venueAbbr)
            return "No custom venue rule matched; field: \(field)"
        }
        let mode = rule.exact == true ? "exact" : "contains"
        let field = metadata.field(forAbbr: rule.abbr)
        return "\(rule.abbr) / Tier \(rule.tier) / \(field), \(mode) \"\(rule.phrase)\""
    }

    private var scoreMemo: String {
        let citations = paper.citedByCount == 1 ? "1 citation" : "\(paper.citedByCount) citations"
        return "Score \(String(format: "%.0f", paper.score)); tier \(paper.tier); \(citations)"
    }

    private var matchedVenueRule: VenuePref? {
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !venue.isEmpty else { return nil }

        if let exact = metadata.venues
            .filter({ $0.exact == true && !$0.phrase.isEmpty && $0.phrase.lowercased() == venue })
            .sorted(by: { $0.tier < $1.tier })
            .first {
            return exact
        }

        return metadata.venues
            .filter { rule in
                rule.exact != true && !rule.phrase.isEmpty && venue.contains(rule.phrase.lowercased())
            }
            .sorted {
                if $0.phrase.count == $1.phrase.count { return $0.tier < $1.tier }
                return $0.phrase.count > $1.phrase.count
            }
            .first
    }
}

// MARK: - Header Action Chrome

private extension View {
    /// Shared 28×28 rounded-square chrome so the header action icons
    /// (cite / collection / PDF) look identical.
    func detailActionChrome() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.10))
            .foregroundStyle(.primary.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.gray.opacity(0.22), lineWidth: 0.5)
            )
    }
}

// MARK: - Collection Picker Popover

/// Click-to-open popover for adding/removing the paper from collections and
/// creating new ones inline. Keeps local member/collection state for instant
/// feedback (`PaperStore.allCollections` is a plain SQLite read, not observed).
private struct CollectionPickerPopover: View {
    let paper: Paper
    let onAddToCollection: (Paper, String) -> Void
    let onRemoveFromCollection: (Paper, String) -> Void

    @State private var collections: [PaperCollection] = []
    @State private var memberIds: Set<String> = []
    @State private var newName: String = ""
    @FocusState private var newNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Collections")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if collections.isEmpty {
                Text("No collections yet")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(collections) { collection in
                            row(for: collection)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Divider()

            HStack(spacing: 6) {
                TextField("New collection", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($newNameFocused)
                    .onSubmit(createAndAdd)
                Button(action: createAndAdd) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 240)
        .onAppear {
            collections = PaperStore.shared.allCollections
            memberIds = Set(paper.collectionIds)
        }
    }

    private func row(for collection: PaperCollection) -> some View {
        let isMember = memberIds.contains(collection.id)
        return Button {
            if isMember {
                onRemoveFromCollection(paper, collection.id)
                memberIds.remove(collection.id)
            } else {
                onAddToCollection(paper, collection.id)
                memberIds.insert(collection.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isMember ? Color.accentColor : .secondary)
                Text(collection.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let created = PaperStore.shared.createCollection(name: name) else { return }
        collections = PaperStore.shared.allCollections
        onAddToCollection(paper, created.id)
        memberIds.insert(created.id)
        newName = ""
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "Select a paper to view details",
            message: "Choose an item from the list to read its abstract,\nadd notes, or open the PDF."
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    ShortcutHint(key: "⌘R", action: "Fetch")
                    ShortcutHint(key: "⌘T", action: "Recommend")
                }
                HStack(spacing: 16) {
                    ShortcutHint(key: "⌘1–6", action: "Switch views")
                    ShortcutHint(key: "⌘↑ ⌘↓", action: "Prev / Next")
                }
                HStack(spacing: 16) {
                    ShortcutHint(key: "⌥⌘1–4", action: "Set status")
                    ShortcutHint(key: "⌘⇧T", action: "Add tag")
                }
            }
            .padding(.top, 8)
        }
    }
}

private struct ShortcutHint: View {
    let key: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
                )

            Text(action)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
        }
    }
}

private struct MemoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .metaLabel()
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.82))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PaperTagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .foregroundStyle(.primary.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.16), lineWidth: 0.5)
            )
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(in: proposal.width ?? 0, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = layout(in: bounds.width, subviews: subviews).rows
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, rows: [Row]) {
        var rows: [Row] = []
        var current = Row(y: 0, height: 0, items: [])
        var x: CGFloat = 0
        let maxWidth = max(width, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                rows.append(current)
                current = Row(y: (rows.last?.bottom ?? 0) + spacing, height: 0, items: [])
                x = 0
            }
            current.items.append(Item(index: index, x: x, size: size))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        let height = rows.last?.bottom ?? 0
        return (CGSize(width: width, height: height), rows)
    }

    private struct Row {
        var y: CGFloat
        var height: CGFloat
        var items: [Item]
        var bottom: CGFloat { y + height }
    }

    private struct Item {
        var index: Int
        var x: CGFloat
        var size: CGSize
    }
}


/// Uppercase secondary mini-label used by detail meta rows (VENUE / DOI / LINK)
/// and the memo key column — one font/color so they stay in sync.
private extension Text {
    func metaLabel() -> some View {
        self.font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary.opacity(0.75))
    }
}

/// A leading "icon + uppercase label + value" row, shared by every detail meta
/// line. The value is supplied by the caller so each row keeps its own
/// rendering (plain text, a hyperlink, etc.).
private struct MetaLabelRow<Content: View>: View {
    let icon: String
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(label).metaLabel()

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailVenueLine: View {
    let value: String

    var body: some View {
        MetaLabelRow(icon: "building.columns", label: "VENUE") {
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .help(value)
        }
    }
}

private struct DetailExternalLinkLine: View {
    let label: String
    let value: String
    let url: URL?

    var body: some View {
        MetaLabelRow(icon: "link", label: label) {
            if let url {
                Link(destination: url) {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                        .help(value)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            } else {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
        }
    }
}
