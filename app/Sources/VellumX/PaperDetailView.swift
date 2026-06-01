import SwiftUI
import AppKit

// MARK: - Paper Detail View

struct PaperDetailView: View {
    let paper: Paper
    private var metadata: MetadataStore { .shared }
    @Binding var isTranslating: Bool
    @Binding var isResolvingPdf: Bool
    @Binding var statusMessage: String

    let onTranslate: (Paper) -> Void
    let onResolvePdf: (Paper) -> Void
    let onStatusChange: (Paper, PaperStatus) -> Void
    let onAddTag: (Paper, String) -> Void
    let onRemoveTag: (Paper, String) -> Void
    let canGoPrevious: Bool
    let canGoNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    @FocusState private var noteFocused: Bool
    @State private var showAddTagPrompt = false
    @State private var newTagName = ""

    // Status configuration
    private let statuses: [(PaperStatus, String, Color)] = [
        (.pending,     "clock",        .blue),
        (.read,        "checkmark.circle", .green),
        (.starred,     "star.fill",    .yellow),
        (.skip,        "eye.slash",    .secondary)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                readerToolbar

                Divider().padding(.horizontal, 20)

                // MARK: Header Card
                headerCard

                Divider().padding(.horizontal, 20)

                // MARK: Action Buttons
                actionBar

                Divider().padding(.horizontal, 20)

                // MARK: Tags
                tagSection

                Divider().padding(.horizontal, 20)

                // MARK: Abstract
                abstractSection

                // MARK: Translation
                if !paper.abstractZh.isEmpty || isTranslating {
                    translationSection
                }

                // MARK: Notes
                notesSection

                // MARK: System Memo
                systemMemoSection
            }
            .padding(.vertical, 16)
        }
        .background(Color(NSColor.textBackgroundColor))
        .alert("Add Tag", isPresented: $showAddTagPrompt) {
            TextField("Tag", text: $newTagName)
            Button("Add") { commitNewTag() }
            Button("Cancel", role: .cancel) { newTagName = "" }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(paper.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .lineSpacing(3)
                .foregroundColor(.primary)

            // Authors
            if !paper.authors.isEmpty {
                Text(paper.authors.joined(separator: ", "))
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }

            metaCard
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Score | Venue | Date | Citations | Topics
            HStack(spacing: 8) {
                ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))

                if !paper.venueAbbr.isEmpty {
                    DetailTag(
                        title: paper.venueAbbr,
                        color: metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr)),
                        fontSize: 11
                    )
                    .help(venueDisplayName.isEmpty ? paper.venueAbbr : venueDisplayName)
                }

                if !paper.publicationDate.isEmpty {
                    DetailInlineMeta(icon: "calendar", value: paper.publicationDate)
                }

                if paper.citedByCount > 0 {
                    DetailInlineMeta(
                        icon: "quote.bubble",
                        value: "\(paper.citedByCount) citation\(paper.citedByCount == 1 ? "" : "s")"
                    )
                }

                if !topics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(topics, id: \.self) { topic in
                            DetailTag(title: topic, color: metadata.topicColor(topic), fontSize: 10)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            // Row 2: Full venue name
            if !venueDisplayName.isEmpty {
                DetailVenueLine(value: venueDisplayName)
                    .help(venueDisplayName)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.16), lineWidth: 0.5)
        )
    }

    private var venueDisplayName: String {
        let venue = paper.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !venue.isEmpty { return venue }

        let abbr = paper.venueAbbr.trimmingCharacters(in: .whitespacesAndNewlines)
        return abbr == "Others" ? "" : abbr
    }

    private var topics: [String] {
        paper.track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Status Bar

    private var readerToolbar: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                navigationButton(systemName: "chevron.left", enabled: canGoPrevious, action: onPrevious)
                statusBar
                navigationButton(systemName: "chevron.right", enabled: canGoNext, action: onNext)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func navigationButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        NavigationButton(systemName: systemName, enabled: enabled, action: action)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(statuses.enumerated()), id: \.offset) { index, item in
                let (status, icon, color) = item
                let isActive = paper.status == status

                Button {
                    onStatusChange(paper, status)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(statusLabel(for: status))
                            .font(.system(size: 12, weight: isActive ? .bold : .medium))
                    }
                    .frame(width: 82)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isActive ? color.opacity(0.18) : Color.clear)
                    .foregroundColor(isActive ? color : .secondary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isActive ? color.opacity(0.4) : Color.gray.opacity(0.25), lineWidth: isActive ? 1.5 : 0.5)
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusLabel(for status: PaperStatus) -> String {
        status.displayName
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                DetailActionButton(
                    icon: "doc.text",
                    label: "Open PDF",
                    isLoading: isResolvingPdf,
                    action: { onResolvePdf(paper) }
                )

                DetailActionButton(
                    icon: "character.book.closed",
                    label: "Translate",
                    isLoading: isTranslating,
                    action: { onTranslate(paper) }
                )

                if let doi = paper.doi, !doi.isEmpty, let doiURL = URL(string: doi) {
                    Link(destination: doiURL) {
                        DetailActionButtonContent(icon: "link", label: "DOI Link", isLoading: false)
                    }
                    .buttonStyle(.plain)
                } else if let url = URL(string: paper.landingPageUrl), !paper.landingPageUrl.isEmpty {
                    Link(destination: url) {
                        DetailActionButtonContent(icon: "link", label: "Open Link", isLoading: false)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionHeader(icon: "tag", title: "Tags")
                Spacer()
                Button {
                    newTagName = ""
                    showAddTagPrompt = true
                } label: {
                    Label("Add Tag", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            if paper.tags.isEmpty {
                Text("No tags yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                FlowLayout(spacing: 7) {
                    ForEach(paper.tags, id: \.self) { tag in
                        PaperTagChip(title: "#\(tag)")
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

    private func commitNewTag() {
        defer { newTagName = "" }
        onAddTag(paper, newTagName)
    }

    // MARK: - Abstract Section

    private var abstractSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "text.alignleft", title: "Abstract")

            Text(paper.abstract.isEmpty ? "No abstract available." : paper.abstract)
                .font(.system(size: 14, design: .serif))
                .lineSpacing(4)
                .foregroundColor(paper.abstract.isEmpty ? .secondary : .primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Translation Section

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(icon: "character", title: "Translation")

            if isTranslating {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Translating...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !paper.abstractZh.isEmpty {
                Text(paper.abstractZh)
                    .font(.system(size: 14, design: .serif))
                    .lineSpacing(4)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.yellow.opacity(0.04))
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
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(noteFocused ? 0.4 : 0.2), lineWidth: 1)
            )
            .onChange(of: noteFocused) {
                if !noteFocused {
                    PaperStore.shared.setPaperNote(id: paper.id, note: paper.note)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
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
            .cornerRadius(8)
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
        if !reason.isEmpty { return reason }
        if paper.isRecommended { return "Active recommendation" }
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

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.secondary.opacity(0.45), .accentColor.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Select a paper to view details")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))

            VStack(spacing: 6) {
                Text("Choose an item from the list to read its abstract,")
                Text("add notes, or open the PDF.")
            }
            .font(.system(size: 13))
            .foregroundColor(.secondary.opacity(0.75))
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                ShortcutHint(key: "⌘R", action: "Fetch")
                ShortcutHint(key: "⌘T", action: "Recommend")
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 0.5)
                )

            Text(action)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
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
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.primary)
        }
    }
}

private struct MemoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.78))
                .frame(width: 104, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundColor(.primary.opacity(0.82))
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
            .foregroundColor(.primary.opacity(0.82))
            .cornerRadius(8)
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

private struct DetailTag: View {
    let title: String
    let color: Color
    let fontSize: CGFloat

    var body: some View {
        Text(title)
            .font(.system(size: fontSize, weight: .bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .foregroundColor(color)
            .cornerRadius(4)
            .lineLimit(1)
    }
}

private struct DetailInlineMeta: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(value)
                .font(.caption)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(4)
    }
}

private struct DetailVenueLine: View {
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "building.columns")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 1)

            Text("VENUE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary.opacity(0.75))

            Text(value)
                .font(.caption)
                .foregroundColor(.primary.opacity(0.8))
                .lineLimit(2)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailActionButtonContent: View {
    let icon: String
    let label: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 5) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .foregroundColor(.primary)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
        )
    }
}

private struct DetailActionButton: View {
    let icon: String
    let label: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DetailActionButtonContent(icon: icon, label: label, isLoading: isLoading)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct NavigationButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(backgroundOpacity))
                .foregroundColor(enabled ? .primary.opacity(0.75) : .secondary.opacity(0.45))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.gray.opacity(0.22), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
    }

    private var backgroundOpacity: Double {
        if !enabled { return 0.04 }
        return isHovering ? 0.16 : 0.10
    }
}
