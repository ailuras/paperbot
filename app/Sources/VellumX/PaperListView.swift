import SwiftUI

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperId: String?
    var metadata: MetadataStore
    let highlightsDailyRecommendations: Bool
    let onCancelRecommendation: (Paper) -> Void
    let onSelectPaper: (String) -> Void
    let onCopyBibtex: (Paper) -> Void
    let onUpdatePaper: (Paper) -> Void
    let onDeletePaper: (Paper) -> Void

    var body: some View {
        List(selection: $selectedPaperId) {
            ForEach(papers) { paper in
                PaperRowView(
                    paper: paper,
                    metadata: metadata,
                    isDailyRecommendation: highlightsDailyRecommendations
                )
                .tag(paper.id)
                .listRowSeparator(.visible)
                .listRowSeparatorTint(Color.primary.opacity(0.08))
                .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
                .contextMenu {
                    Button {
                        onCopyBibtex(paper)
                    } label: {
                        Label(L10n.t(.cite), systemImage: "doc.on.doc")
                    }
                    Button {
                        onUpdatePaper(paper)
                    } label: {
                        Label(L10n.t(.cmdUpdatePaper), systemImage: "arrow.clockwise")
                    }
                    if highlightsDailyRecommendations {
                        Button(L10n.t(.cancelRecommendation)) {
                            onCancelRecommendation(paper)
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeletePaper(paper)
                    } label: {
                        Label(L10n.t(.cmdDeletePaper), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.inset)
        .onChange(of: selectedPaperId) { _, newValue in
            if let newValue { onSelectPaper(newValue) }
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

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    private var isTodayRecommended: Bool {
        guard let recommendedAt = paper.recommendedAt else { return false }
        return Calendar.current.isDateInToday(recommendedAt)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Status-colored accent bar for today's picks
            if isDailyRecommendation && isTodayRecommended {
                Rectangle()
                    .fill(paper.status.iconColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 4) {
                        PaperTagView(title: paper.venueAbbr, color: venueColor)
                        ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))
                    }
                    Text(paper.publicationDate)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, isDailyRecommendation && isTodayRecommended ? 2 : 5)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        // Subtle status-tinted background for today's recommended cards
        .background(isDailyRecommendation && isTodayRecommended
            ? paper.status.iconColor.opacity(0.05)
            : Color.clear)
        .contentShape(Rectangle())
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
