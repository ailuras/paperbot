import SwiftUI

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperId: String?
    @Binding var searchKeyword: String
    @Binding var showFilters: Bool
    @Binding var selectedFields: Set<String>
    @Binding var selectedTiers: Set<Int>
    var metadata: MetadataStore

    let isFetching: Bool
    let isRecommending: Bool
    let highlightsDailyRecommendations: Bool
    let onFetch: () -> Void
    let onRecommend: () -> Void
    let onCancelRecommendation: (Paper) -> Void
    let onSelectPaper: (String) -> Void

    @Binding var sortByScore: Bool
    @State private var showSortOptions = false
    private let lastTodayId: String?

    init(
        papers: [Paper],
        selectedPaperId: Binding<String?>,
        searchKeyword: Binding<String>,
        showFilters: Binding<Bool>,
        selectedFields: Binding<Set<String>>,
        selectedTiers: Binding<Set<Int>>,
        metadata: MetadataStore,
        isFetching: Bool,
        isRecommending: Bool,
        highlightsDailyRecommendations: Bool,
        onFetch: @escaping () -> Void,
        onRecommend: @escaping () -> Void,
        onCancelRecommendation: @escaping (Paper) -> Void,
        onSelectPaper: @escaping (String) -> Void,
        sortByScore: Binding<Bool>
    ) {
        self.papers = papers
        self._selectedPaperId = selectedPaperId
        self._searchKeyword = searchKeyword
        self._showFilters = showFilters
        self._selectedFields = selectedFields
        self._selectedTiers = selectedTiers
        self.metadata = metadata
        self.isFetching = isFetching
        self.isRecommending = isRecommending
        self.highlightsDailyRecommendations = highlightsDailyRecommendations
        self.onFetch = onFetch
        self.onRecommend = onRecommend
        self.onCancelRecommendation = onCancelRecommendation
        self.onSelectPaper = onSelectPaper
        self._sortByScore = sortByScore

        if highlightsDailyRecommendations && !sortByScore.wrappedValue {
            let todayPapers = papers.filter {
                $0.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
            }
            self.lastTodayId = todayPapers.last?.id
        } else {
            self.lastTodayId = nil
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private var filtersActive: Bool { !selectedFields.isEmpty || !selectedTiers.isEmpty }

    private func tierDefaultColor(_ tier: Int) -> LabelColor {
        switch tier {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray
        }
    }

    private var filterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                Button("Clear") { selectedFields = []; selectedTiers = [] }
                    .controlSize(.small)
                    .disabled(!filtersActive)
            }
            if !metadata.allFields.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIELDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(metadata.allFields, id: \.self) { field in
                        FilterRow(title: field, colorKey: "field:\(field)",
                                  defaultColor: .teal,
                                  isSelected: selectedFields.contains(field)) {
                            toggle(field, in: &selectedFields)
                        }
                    }
                }
            }
            if !metadata.allTiers.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("TIER").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(metadata.allTiers, id: \.self) { tier in
                        FilterRow(title: "Tier \(tier)", colorKey: "tier:\(tier)",
                                  defaultColor: tierDefaultColor(tier),
                                  isSelected: selectedTiers.contains(tier)) {
                            toggle(tier, in: &selectedTiers)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 230)
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sort")
                .font(.headline)

            Button {
                sortByScore = true
                showSortOptions = false
            } label: {
                Label("Score", systemImage: sortByScore ? "checkmark.circle.fill" : "number")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                sortByScore = false
                showSortOptions = false
            } label: {
                Label("Date", systemImage: sortByScore ? "calendar" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 170)
    }

    private func toolbarIcon(_ systemName: String, isActive: Bool = false) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(Color.accentColor.opacity(0.9))
                    .frame(width: 19, height: 19)
            }

            Image(systemName: systemName)
                .font(.system(size: 8.8, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.72))
        }
        .frame(width: 23, height: 23)
        .contentShape(Circle())
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
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
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
        .searchable(text: $searchKeyword, placement: .toolbar, prompt: "Search title, abstract or authors...")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                ControlGroup {
                    Button(action: onFetch) {
                        if isFetching {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("arrow.clockwise")
                        }
                    }
                    .disabled(isFetching || isRecommending)
                    .accessibilityLabel("Fetch new papers")
                    .help("Fetch new papers from OpenAlex")

                    Button(action: onRecommend) {
                        if isRecommending {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("wand.and.stars")
                        }
                    }
                    .disabled(isFetching || isRecommending)
                    .accessibilityLabel("Generate recommendations")
                    .help("Generate daily paper recommendations")

                    Button { showFilters.toggle() } label: {
                        toolbarIcon(filtersActive
                                    ? "line.3.horizontal.decrease"
                                    : "line.3.horizontal.decrease",
                                    isActive: filtersActive)
                    }
                    .accessibilityLabel("Filter papers")
                    .help("Filter by field and tier")
                    .popover(isPresented: $showFilters, arrowEdge: .bottom) { filterPopover }

                    Button { showSortOptions.toggle() } label: {
                        toolbarIcon("arrow.up.arrow.down", isActive: showSortOptions)
                    }
                    .accessibilityLabel("Sort papers")
                    .help("Sort papers")
                    .popover(isPresented: $showSortOptions, arrowEdge: .bottom) { sortPopover }
                }
            }
        }
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

private struct PaperRowView: View {
    let paper: Paper
    var metadata: MetadataStore
    let isDailyRecommendation: Bool
    let isLastToday: Bool

    private var topics: [String] {
        paper.track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    private var isTodayRecommended: Bool {
        guard let recommendedAt = paper.recommendedAt else { return false }
        return Calendar.current.isDateInToday(recommendedAt)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Today recommendation left accent bar
            if isDailyRecommendation && isTodayRecommended {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 6)
            }

            VStack(alignment: .leading, spacing: 7) {
                // Title row (full width, up to 2 lines)
                Text(paper.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundColor(.primary)

                // Meta row: Score → Venue → Date → Topics
                HStack(spacing: 6) {
                    ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))

                    PaperTagView(title: paper.venueAbbr, color: venueColor)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(paper.publicationDate)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        ForEach(topics.prefix(3), id: \.self) { topic in
                            PaperTagView(title: topic, color: metadata.topicColor(topic))
                        }
                    }

                    Spacer()
                }

                // Divider after last today's recommendation
                if isLastToday {
                    Divider()
                        .padding(.top, 4)
                        .padding(.bottom, 1)
                }
            }
            .padding(.leading, isDailyRecommendation && isTodayRecommended ? 10 : 14)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
        }
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
