import SwiftUI

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperId: String?
    var metadata: MetadataStore
    let highlightsDailyRecommendations: Bool
    let sortByScore: Bool
    let onCancelRecommendation: (Paper) -> Void
    let onSelectPaper: (String) -> Void

    private let lastTodayId: String?

    init(
        papers: [Paper],
        selectedPaperId: Binding<String?>,
        metadata: MetadataStore,
        highlightsDailyRecommendations: Bool,
        sortByScore: Bool,
        onCancelRecommendation: @escaping (Paper) -> Void,
        onSelectPaper: @escaping (String) -> Void
    ) {
        self.papers = papers
        self._selectedPaperId = selectedPaperId
        self.metadata = metadata
        self.highlightsDailyRecommendations = highlightsDailyRecommendations
        self.sortByScore = sortByScore
        self.onCancelRecommendation = onCancelRecommendation
        self.onSelectPaper = onSelectPaper

        if highlightsDailyRecommendations && !sortByScore {
            let todayPapers = papers.filter {
                $0.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
            }
            self.lastTodayId = todayPapers.last?.id
        } else {
            self.lastTodayId = nil
        }
    }

    var body: some View {
        List(selection: $selectedPaperId) {
            ForEach(papers) { paper in
                PaperRowView(
                    paper: paper,
                    metadata: metadata,
                    isDailyRecommendation: highlightsDailyRecommendations,
                    isLastToday: paper.id == lastTodayId
                )
                .tag(paper.id)
                .listRowSeparator(.visible)
                .listRowSeparatorTint(Color.primary.opacity(0.07))
                .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
                .contextMenu {
                    if highlightsDailyRecommendations {
                        Button(L10n.t(.cancelRecommendation)) {
                            onCancelRecommendation(paper)
                        }
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
    let isLastToday: Bool

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    private var isTodayRecommended: Bool {
        guard let recommendedAt = paper.recommendedAt else { return false }
        return Calendar.current.isDateInToday(recommendedAt)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isDailyRecommendation && isTodayRecommended {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 4) {
                        PaperTagView(title: paper.venueAbbr, color: venueColor)
                        ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))
                    }
                    Text(paper.publicationDate)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.leading, isDailyRecommendation && isTodayRecommended ? 2 : 5)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if isLastToday {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(height: 1)
            }
        }
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
            .cornerRadius(4)
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
                .foregroundColor(.primary.opacity(0.8))

            Text("Press ⌘R to fetch papers or adjust your filters")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.92))
    }
}
