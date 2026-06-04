import SwiftUI

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperIds: Set<String>
    var metadata: MetadataStore
    let highlightsDailyRecommendations: Bool
    let onCancelRecommendation: (Paper) -> Void
    let onSelectionChange: (Set<String>) -> Void
    let onCopyBibtex: ([Paper]) -> Void
    let onUpdatePaper: ([Paper]) -> Void
    let onDeletePaper: ([Paper]) -> Void
    let onSetStatus: ([Paper], PaperStatus) -> Void
    let onAddToCollection: ([Paper], String) -> Void
    let collections: [PaperCollection]

    var body: some View {
        List(selection: $selectedPaperIds) {
            ForEach(papers) { paper in
                PaperRowView(
                    paper: paper,
                    metadata: metadata,
                    isDailyRecommendation: highlightsDailyRecommendations,
                    isSelected: selectedPaperIds.contains(paper.id)
                )
                .tag(paper.id)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 9, bottom: 3, trailing: 9))
                .listRowBackground(Color.clear)
                .contextMenu {
                    // Finder-style: act on the whole selection if this row is in
                    // it, otherwise just this row.
                    let targets = selectedPaperIds.contains(paper.id)
                        ? papers.filter { selectedPaperIds.contains($0.id) }
                        : [paper]
                    let suffix = targets.count > 1 ? " (\(targets.count))" : ""
                    Button {
                        onCopyBibtex(targets)
                    } label: {
                        Label(L10n.t(.cite) + suffix, systemImage: "doc.on.doc")
                    }
                    Button {
                        onUpdatePaper(targets)
                    } label: {
                        Label(L10n.t(.cmdUpdatePaper) + suffix, systemImage: "arrow.clockwise")
                    }
                    Menu {
                        ForEach(PaperStatus.allCases, id: \.self) { status in
                            Button(status.displayName) { onSetStatus(targets, status) }
                        }
                    } label: {
                        Label(L10n.t(.cmdSetStatus), systemImage: "flag")
                    }
                    if !collections.isEmpty {
                        Menu {
                            ForEach(collections) { collection in
                                Button(collection.name) { onAddToCollection(targets, collection.id) }
                            }
                        } label: {
                            Label(L10n.t(.cmdAddToCollection), systemImage: "folder")
                        }
                    }
                    if highlightsDailyRecommendations {
                        Button(L10n.t(.cancelRecommendation)) {
                            onCancelRecommendation(paper)
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeletePaper(targets)
                    } label: {
                        Label(L10n.t(.cmdDeletePaper) + suffix, systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedPaperIds) { _, ids in
            onSelectionChange(ids)
        }
        .overlay {
            if papers.isEmpty {
                EmptyPaperListView()
            }
        }
    }
}

// MARK: - Row

private struct PaperRowView: View {
    let paper: Paper
    var metadata: MetadataStore
    let isDailyRecommendation: Bool
    let isSelected: Bool

    @State private var isHovering = false

    private let cornerRadius: CGFloat = 9

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    private var isTodayRecommended: Bool {
        guard isDailyRecommendation, let recommendedAt = paper.recommendedAt else { return false }
        return Calendar.current.isDateInToday(recommendedAt)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status-colored left edge marks today's picks; clipped to the card.
            if isTodayRecommended {
                Rectangle()
                    .fill(paper.status.iconColor)
                    .frame(width: 3)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    if !paper.venueAbbr.isEmpty {
                        PaperTagView(title: paper.venueAbbr, color: venueColor)
                    }
                    ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))
                    Spacer(minLength: 8)
                    Text(paper.publicationDate)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var fillColor: Color {
        // Selection is shown by the border only — no row/card background tint.
        if isTodayRecommended { return paper.status.iconColor.opacity(0.06) }
        let base = Color(nsColor: .controlBackgroundColor)
        return isHovering ? base.opacity(0.7) : base.opacity(0.45)
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor.opacity(0.9) }
        if isTodayRecommended { return paper.status.iconColor.opacity(0.45) }
        return Color.gray.opacity(isHovering ? 0.32 : 0.18)
    }
}

private struct PaperTagView: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Empty State

private struct EmptyPaperListView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.secondary.opacity(0.5), .accentColor.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("No papers here")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.8))

            Text("Press ⌘R to fetch papers or adjust your filters")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.92))
    }
}
