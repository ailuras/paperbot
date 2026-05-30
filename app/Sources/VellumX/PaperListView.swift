import SwiftUI

struct PaperListView: View {
    let papers: [Paper]
    @Binding var selectedPaperId: String?
    @Binding var searchKeyword: String
    @Binding var showFilters: Bool
    @Binding var selectedFields: Set<String>
    @Binding var selectedTiers: Set<Int>
    var settings: AppSettings
    
    let isFetching: Bool
    let isRecommending: Bool
    let onFetch: () -> Void
    let onRecommend: () -> Void
    let onSelectPaper: (String) -> Void
    
    @Binding var sortByScore: Bool
    
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
            if !settings.allFields.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("FIELDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(settings.allFields, id: \.self) { field in
                        FilterRow(title: field, colorKey: "field:\(field)",
                                  defaultColor: .teal,
                                  isSelected: selectedFields.contains(field)) {
                            toggle(field, in: &selectedFields)
                        }
                    }
                }
            }
            if !settings.allTiers.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("TIER").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(settings.allTiers, id: \.self) { tier in
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
    
    var body: some View {
        List(selection: $selectedPaperId) {
            ForEach(papers) { paper in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(paper.title)
                            .font(.headline)
                            .lineLimit(2)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        ScoreBadgeView(score: paper.score)
                    }
                    
                    HStack {
                        Text(paper.venueAbbr)
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text(paper.publicationDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(paper.track)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }
                .padding(.vertical, 4)
                .tag(paper.id)
            }
        }
        .listStyle(.inset)
        .searchable(text: $searchKeyword, placement: .toolbar, prompt: "Search title, abstract or authors...")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: onFetch) {
                    if isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .symbolVariant(.circle.fill)
                    }
                }
                .disabled(isFetching || isRecommending)
                .help("Fetch new papers from OpenAlex")
                
                Button(action: onRecommend) {
                    if isRecommending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .symbolVariant(.circle.fill)
                    }
                }
                .disabled(isFetching || isRecommending)
                .help("Generate daily paper recommendations")
                
                Button { showFilters.toggle() } label: {
                    Label("Filter", systemImage: filtersActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Filter by field and tier")
                .popover(isPresented: $showFilters, arrowEdge: .bottom) { filterPopover }
                
                Menu {
                    Picker("Sort", selection: $sortByScore) {
                        Label("Score", systemImage: "number").tag(true)
                        Label("Date", systemImage: "calendar").tag(false)
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort papers")
            }
        }
        .onChange(of: selectedPaperId) { _, newValue in
            if let newValue { onSelectPaper(newValue) }
        }
    }
}
