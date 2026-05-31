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
    let onSelectPaper: (String) -> Void

    @Binding var sortByScore: Bool
    @State private var showSortOptions = false

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
                    isDailyRecommendation: highlightsDailyRecommendations
                )
                .tag(paper.id)
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
    }
}

private struct PaperRowView: View {
    let paper: Paper
    var metadata: MetadataStore
    let isDailyRecommendation: Bool

    private var topics: [String] {
        paper.track.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var venueColor: Color {
        metadata.fieldColor(metadata.field(forAbbr: paper.venueAbbr))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(paper.title)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Spacer()

                ScoreBadgeView(score: paper.score, color: metadata.tierColor(paper.tier))
            }

            HStack {
                PaperTagView(title: paper.venueAbbr, color: venueColor)

                Text("•")
                    .foregroundColor(.secondary)

                Text(paper.publicationDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    ForEach(topics, id: \.self) { topic in
                        PaperTagView(title: topic, color: metadata.topicColor(topic))
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isDailyRecommendation ? 8 : 0)
        .background {
            if isDailyRecommendation {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.06))
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
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .cornerRadius(3)
    }
}
