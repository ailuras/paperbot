import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var store = PaperStore.shared
    @ObservedObject private var settings = AppSettings.shared

    // Filter and Sort states
    @State private var selectedSidebarItem: SidebarItem? = .recommended
    @State private var searchKeyword: String = ""
    @State private var sortByScore: Bool = true

    // Topic is single-select; Fields/Tier are multi-select (in the toolbar
    // filter popover). Union within a group, intersect across groups.
    @State private var selectedTopic: String?
    @State private var selectedFields: Set<String> = []
    @State private var selectedTiers: Set<Int> = []
    @State private var showFilters = false
    
    // Selection state
    @State private var selectedPaperId: String?
    /// Last paper actually opened; retained when the list selection clears.
    @State private var lastViewedPaperId: String?
    
    // Async execution states
    @State private var isFetching: Bool = false
    @State private var isRecommending: Bool = false
    @State private var isTranslating: Bool = false
    @State private var isResolvingPdf: Bool = false
    @State private var statusMessage: String = ""
    
    enum SidebarItem: Hashable {
        case all
        case recommended
        case pending
        case starred
        case read
        case skipped

        var displayName: String {
            switch self {
            case .all: return "All Papers"
            case .recommended: return "Today's Recommended"
            case .pending: return "Pending"
            case .starred: return "Starred"
            case .read: return "Read"
            case .skipped: return "Skipped"
            }
        }

        var iconName: String {
            switch self {
            case .all: return "books.vertical"
            case .recommended: return "sparkles"
            case .pending: return "clock"
            case .starred: return "star"
            case .read: return "checkmark.circle"
            case .skipped: return "eye.slash"
            }
        }

        var iconColor: Color {
            switch self {
            case .all: return .primary
            case .recommended: return .orange
            case .pending: return .blue
            case .starred: return .yellow
            case .read: return .green
            case .skipped: return .secondary
            }
        }
    }
    
    // Computed property for filtered papers
    var filteredPapers: [Paper] {
        var result = store.papers
        
        // 1. Filter by Sidebar selection
        if let selected = selectedSidebarItem {
            switch selected {
            case .all:
                break
            case .recommended:
                result = result.filter { $0.status == "recommended" }
            case .pending:
                result = result.filter { $0.status == "pending" }
            case .starred:
                result = result.filter { $0.status == "starred" }
            case .read:
                result = result.filter { $0.status == "read" }
            case .skipped:
                result = result.filter { $0.status == "skip" }
            }
        }

        // 1b. Taxonomy filters (multi-select): union within a group, intersect
        // across groups. An empty group doesn't filter.
        if let topic = selectedTopic {
            result = result.filter { paper in
                paper.track.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .contains(topic)
            }
        }
        if !selectedFields.isEmpty {
            result = result.filter { paper in
                guard let f = settings.field(forAbbr: paper.venueAbbr) else { return false }
                return selectedFields.contains(f)
            }
        }
        if !selectedTiers.isEmpty {
            result = result.filter { selectedTiers.contains($0.tier) }
        }

        // 2. Filter by search keyword
        if !searchKeyword.isEmpty {
            let kw = searchKeyword.lowercased()
            result = result.filter { 
                $0.title.lowercased().contains(kw) || 
                $0.abstract.lowercased().contains(kw) ||
                $0.authors.joined(separator: " ").lowercased().contains(kw)
            }
        }
        
        // 3. Sort
        if sortByScore {
            result.sort {
                if $0.score == $1.score {
                    return $0.citedByCount > $1.citedByCount
                }
                return $0.score > $1.score
            }
        } else {
            result.sort { $0.publicationDate > $1.publicationDate }
        }
        
        return result
    }
    
    /// The paper whose details are shown. Driven by `lastViewedPaperId` (not the
    /// live list selection) so clicking empty space in the list — which clears
    /// the selection — keeps the last opened paper's details visible.
    var selectedPaper: Paper? {
        guard let id = lastViewedPaperId else { return nil }
        return store.papers.first(where: { $0.id == id })
    }
    
    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func tierDefaultColor(_ tier: Int) -> LabelColor {
        switch tier {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray
        }
    }

    private var filtersActive: Bool { !selectedFields.isEmpty || !selectedTiers.isEmpty }

    /// Toolbar filter popover: Fields + Tier multi-select (with right-click
    /// color), keeping these out of the sidebar for a cleaner look.
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
        NavigationSplitView {
            // MARK: - Left Sidebar
            List(selection: $selectedSidebarItem) {
                Section("Library") {
                    ForEach([SidebarItem.recommended, .pending, .starred, .read, .skipped, .all], id: \.self) { item in
                        NavigationLink(value: item) {
                            Label {
                                Text(item.displayName)
                            } icon: {
                                Image(systemName: item.iconName)
                                    .foregroundStyle(item.iconColor)
                            }
                        }
                    }
                }

                if !settings.tracks.isEmpty {
                    Section("Topics") {
                        ForEach(settings.tracks.map(\.name), id: \.self) { name in
                            FilterRow(title: name, colorKey: "topic:\(name)",
                                      defaultColor: .purple,
                                      isSelected: selectedTopic == name) {
                                selectedTopic = (selectedTopic == name) ? nil : name
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                // Status message bar in Sidebar bottom
                if !statusMessage.isEmpty {
                    VStack(spacing: 0) {
                        Divider()
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        } content: {
            // MARK: - Middle List
            List(selection: $selectedPaperId) {
                ForEach(filteredPapers) { paper in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(paper.title)
                                .font(.headline)
                                .lineLimit(2)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            // Score badge
                            Text(String(format: "%.1f", paper.score))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(scoreColor(paper.score).opacity(0.15))
                                .foregroundColor(scoreColor(paper.score))
                                .cornerRadius(4)
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
                            
                            // Track Tag
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
            .onChange(of: selectedPaperId) { _, newValue in
                // Remember the last opened paper; ignore deselection (nil) so
                // clicking empty space keeps the detail view populated.
                if let newValue { lastViewedPaperId = newValue }
            }
        } detail: {
            // MARK: - Right Detail
            if let paper = selectedPaper {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title & Status
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(paper.venue)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)
                                
                                Spacer()
                                
                                // Status Selector
                                Picker("", selection: Binding(
                                    get: { paper.status },
                                    set: { store.setPaperStatus(id: paper.id, status: $0) }
                                )) {
                                    Text("Pending").tag("pending")
                                    Text("Recommended").tag("recommended")
                                    Text("Read").tag("read")
                                    Text("Starred").tag("starred")
                                    Text("Skip").tag("skip")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 320)
                            }
                            
                            Text(paper.title)
                                .font(.title)
                                .bold()
                                .foregroundColor(.primary)
                            
                            if !paper.titleZh.isEmpty {
                                Text(paper.titleZh)
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(.orange)
                                    .padding(.top, 4)
                            }
                            
                            Text(paper.authors.joined(separator: ", "))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Control buttons
                        HStack(spacing: 12) {
                            // PDF Resolution button
                            Button(action: { resolvePdf(for: paper) }) {
                                if isResolvingPdf {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(paper.pdfUrl == nil ? "Resolve PDF" : "Open PDF", systemImage: "doc.plaintext")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isResolvingPdf)
                            
                            // DeepSeek Translation button
                            Button(action: { translate(paper: paper) }) {
                                if isTranslating {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Translate", systemImage: "character.book.closed")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isTranslating)
                            
                            if let doi = paper.doi {
                                Link(destination: URL(string: doi.hasPrefix("http") ? doi : "https://doi.org/\(doi)")!) {
                                    Label("DOI Link", systemImage: "safari")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        // Abstract
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Abstract")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(paper.abstract)
                                .font(.body)
                                .lineSpacing(4)
                                .foregroundColor(.secondary)
                            
                            if !paper.abstractZh.isEmpty {
                                Divider().padding(.vertical, 8)
                                Text("摘要翻译 (DeepSeek)")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                
                                Text(paper.abstractZh)
                                    .font(.body)
                                    .lineSpacing(4)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Personal Notes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            
                            TextEditor(text: Binding(
                                get: { paper.note },
                                set: { store.setPaperNote(id: paper.id, note: $0) }
                            ))
                            .frame(minHeight: 120)
                            .font(.system(.body, design: .monospaced))
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .border(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.secondary.opacity(0.3))
                    Text("Select a paper to view details")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Field / Tier filter popover
                Button {
                    showFilters.toggle()
                } label: {
                    Label("Filter", systemImage: filtersActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .help("Filter by field and tier")
                .popover(isPresented: $showFilters, arrowEdge: .bottom) { filterPopover }

                // Sorting Menu
                Menu {
                    Button(action: { sortByScore = true }) {
                        HStack {
                            Text("Sort by Score")
                            if sortByScore { Image(systemName: "checkmark") }
                        }
                    }
                    Button(action: { sortByScore = false }) {
                        HStack {
                            Text("Sort by Date")
                            if !sortByScore { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                
                Divider()
                
                // Fetch button
                Button(action: fetchPapers) {
                    if isFetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Fetch", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isFetching || isRecommending)
                .help("Fetch new papers from OpenAlex")
                
                // Recommend button
                Button(action: recommendPapers) {
                    if isRecommending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Recommend", systemImage: "wand.and.stars")
                    }
                }
                .disabled(isFetching || isRecommending)
                .help("Generate daily paper recommendations")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func scoreColor(_ score: Double) -> Color {
        if score >= 20.0 { return .red }
        if score >= 10.0 { return .orange }
        return .green
    }
    
    private func fetchPapers() {
        let config = ConfigManager.shared.effectiveConfig
        guard !config.tracks.isEmpty else {
            statusMessage = "No tracks configured — add one in Settings ▸ Papers"
            return
        }
        isFetching = true
        statusMessage = "Fetching OpenAlex papers..."
        
        Task {
            do {
                let fetcher = OpenAlexFetcher(config: config)
                let result = try await fetcher.fetch()
                let stats = store.addOrUpdate(papers: result.papers)
                statusMessage = "Fetched! Added \(stats.inserted) | Updated \(stats.updated)"
            } catch {
                statusMessage = "Fetch failed: \(error.localizedDescription)"
            }
            isFetching = false
        }
    }
    
    private func recommendPapers() {
        let config = ConfigManager.shared.effectiveConfig
        isRecommending = true
        statusMessage = "Running recommendation engine..."
        
        Task {
            let engine = RecommendEngine(config: config)
            let result = engine.recommend(papers: store.papers)
            statusMessage = "Selected \(result.count) recommendations for today!"
            isRecommending = false
        }
    }
    
    private func translate(paper: Paper) {
        isTranslating = true
        statusMessage = "Translating with DeepSeek..."
        
        Task {
            do {
                let translator = DeepSeekTranslator()
                try await translator.translate(paper: paper)
                statusMessage = "Translated successfully!"
            } catch {
                statusMessage = "Translation failed: \(error.localizedDescription)"
            }
            isTranslating = false
        }
    }
    
    private func resolvePdf(for paper: Paper) {
        if let pdfUrl = paper.pdfUrl, !pdfUrl.isEmpty, let url = URL(string: pdfUrl) {
            NSWorkspace.shared.open(url)
            return
        }
        
        isResolvingPdf = true
        statusMessage = "Resolving OpenAccess PDF..."
        
        Task {
            let resolver = PdfResolver()
            if let pdfUrl = await resolver.resolve(paper: paper), let url = URL(string: pdfUrl) {
                statusMessage = "PDF resolved!"
                NSWorkspace.shared.open(url)
            } else {
                statusMessage = "Could not resolve PDF for this paper"
            }
            isResolvingPdf = false
        }
    }
}
