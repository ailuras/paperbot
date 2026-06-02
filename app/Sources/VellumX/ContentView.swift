import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = PaperStore.shared
    @State private var metadata = MetadataStore.shared
    @State private var windowOpener = MainWindowOpener.shared
    private var settings = AppSettings.shared

    // Filter and Sort states
    @State private var selectedSidebarItem: SidebarItem? = .recommended
    @State private var selectedCollectionId: String? = nil
    @State private var searchKeyword: String = ""
    @State private var sortByScore: Bool = false

    // Topic is single-select; Fields/Tier are multi-select (in the toolbar
    // filter popover). Union within a group, intersect across groups.
    @State private var selectedTopic: String?
    @State private var selectedFields: Set<String> = []
    @State private var selectedTiers: Set<Int> = []
    @State private var includedTags: Set<String> = []
    @State private var excludedTags: Set<String> = []
    @State private var showFilters = false
    @State private var showSortOptions = false

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

    // Cached filtered results — recalculated only when inputs change.
    @State private var filteredPapers: [Paper] = []

    /// Aggregates all filter inputs into a single hashable value so `.onChange`
    /// can watch one expression instead of chaining many.
    private var filterInputs: FilterInputs {
        FilterInputs(
            paperCount: store.papers.count,
            paperVersion: store.paperVersion,
            settingsVersion: settings.configVersion,
            metadataVersion: metadata.metadataVersion,
            sidebarItem: selectedSidebarItem,
            collectionId: selectedCollectionId,
            topic: selectedTopic,
            includedTags: includedTags,
            excludedTags: excludedTags,
            fields: selectedFields,
            tiers: selectedTiers,
            search: searchKeyword,
            sortByScore: sortByScore
        )
    }

    private struct FilterInputs: Equatable {
        var paperCount: Int
        var paperVersion: Int
        var settingsVersion: Int
        var metadataVersion: Int
        var sidebarItem: SidebarItem?
        var collectionId: String?
        var topic: String?
        var includedTags: Set<String>
        var excludedTags: Set<String>
        var fields: Set<String>
        var tiers: Set<Int>
        var search: String
        var sortByScore: Bool
    }

    /// The paper whose details are shown. Driven by `lastViewedPaperId` (not the
    /// live list selection) so clicking empty space in the list — which clears
    /// the selection — keeps the last opened paper's details visible.
    var selectedPaper: Paper? {
        guard let id = lastViewedPaperId else { return nil }
        return store.papers.first(where: { $0.id == id })
    }

    private var selectedPaperIndex: Int? {
        guard let id = lastViewedPaperId else { return nil }
        return filteredPapers.firstIndex(where: { $0.id == id })
    }

    private var canGoPrevious: Bool { selectedPaperIndex.map { $0 > 0 } ?? false }
    private var canGoNext: Bool {
        selectedPaperIndex.map { $0 < filteredPapers.count - 1 } ?? false
    }

    // MARK: - Toolbar helpers (unified; used for both list and detail groups)

    private var filtersActive: Bool { !selectedFields.isEmpty || !selectedTiers.isEmpty }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    @ViewBuilder
    private func toolbarIcon(_ systemName: String,
                             isActive: Bool = false,
                             isEnabled: Bool = true,
                             activeColor: Color = .accentColor) -> some View {
        ZStack {
            if isActive {
                Circle()
                    .fill(activeColor.opacity(0.85))
                    .frame(width: 19, height: 19)
            }
            Image(systemName: systemName)
                .font(.system(size: 8.8, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isActive  ? Color.white :
                    isEnabled ? Color.primary.opacity(0.72) :
                                Color.primary.opacity(0.22)
                )
        }
        .frame(width: 23, height: 23)
        .contentShape(Circle())
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
                                  defaultColor: MetadataStore.tierDefaultColor(tier),
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
            Text("Sort").font(.headline)
            Button {
                sortByScore = true; showSortOptions = false
            } label: {
                Label("Score", systemImage: sortByScore ? "checkmark.circle.fill" : "number")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                sortByScore = false; showSortOptions = false
            } label: {
                Label("Date", systemImage: sortByScore ? "calendar" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 170)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedItem: $selectedSidebarItem,
                selectedCollectionId: $selectedCollectionId,
                selectedTopic: $selectedTopic,
                includedTags: $includedTags,
                excludedTags: $excludedTags,
                tags: store.allTags,
                collections: store.allCollections,
                metadata: metadata,
                statusMessage: statusMessage,
                papers: store.papers
            )
        } content: {
            PaperListView(
                papers: filteredPapers,
                selectedPaperId: $selectedPaperId,
                metadata: metadata,
                highlightsDailyRecommendations: selectedSidebarItem == .recommended && selectedCollectionId == nil,
                sortByScore: sortByScore,
                onCancelRecommendation: cancelRecommendation,
                onSelectPaper: { lastViewedPaperId = $0 }
            )
        } detail: {
            if let paper = selectedPaper {
                PaperDetailView(
                    paper: paper,
                    isTranslating: $isTranslating,
                    isResolvingPdf: $isResolvingPdf,
                    statusMessage: $statusMessage,
                    onTranslate: translate,
                    onResolvePdf: resolvePdf,
                    onStatusChange: updatePaperStatus,
                    onAddTag: addPaperTag,
                    onRemoveTag: removePaperTag,
                    onAddToCollection: addPaperToCollection,
                    onRemoveFromCollection: removePaperFromCollection
                )
            } else {
                EmptyDetailView()
            }
        }
        .onAppear {
            applyFilters()
            focusRequestedPaper()
        }
        .onChange(of: filterInputs) { applyFilters() }
        .onChange(of: windowOpener.requestedPaperId) { focusRequestedPaper() }
        .onChange(of: selectedSidebarItem) { _, new in
            if new != nil { selectedCollectionId = nil }
        }
        .searchable(text: $searchKeyword, placement: .toolbar,
                    prompt: "Search title, abstract or authors...")
        .toolbar {
            // ── List operations ────────────────────────────────────────────
            ToolbarItem(placement: .automatic) {
                ControlGroup {
                    Button(action: fetchPapers) {
                        if isFetching {
                            ProgressView().controlSize(.small).frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("arrow.clockwise")
                        }
                    }
                    .disabled(isFetching || isRecommending)
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityLabel("Fetch new papers")
                    .help("Fetch new papers from OpenAlex")

                    Button(action: recommendPapers) {
                        if isRecommending {
                            ProgressView().controlSize(.small).frame(width: 22, height: 22)
                        } else {
                            toolbarIcon("wand.and.stars")
                        }
                    }
                    .disabled(isFetching || isRecommending)
                    .keyboardShortcut("t", modifiers: .command)
                    .accessibilityLabel("Generate recommendations")
                    .help("Generate daily paper recommendations")

                    Button { showFilters.toggle() } label: {
                        toolbarIcon("line.3.horizontal.decrease", isActive: filtersActive)
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

            // ── Detail navigation + status (always visible; disabled when nothing is open) ──
            // `paper` is resolved once here — avoids repeated O(n) scans inside ForEach.
            ToolbarItem(placement: .automatic) {
                let paper = selectedPaper
                ControlGroup {
                    Button(action: selectPreviousPaper) {
                        toolbarIcon("chevron.left", isEnabled: canGoPrevious)
                    }
                    .disabled(!canGoPrevious)
                    .help("Previous paper")

                    ForEach(PaperStatus.allCases, id: \.self) { status in
                        let isActive = paper?.status == status
                        Button {
                            if let paper { updatePaperStatus(paper, status: status) }
                        } label: {
                            toolbarIcon(status.iconName,
                                       isActive: isActive,
                                       isEnabled: paper != nil,
                                       activeColor: status.iconColor)
                        }
                        .disabled(paper == nil)
                        .help(status.displayName)
                    }

                    Button(action: selectNextPaper) {
                        toolbarIcon("chevron.right", isEnabled: canGoNext)
                    }
                    .disabled(!canGoNext)
                    .help("Next paper")
                }
            }
        }
    }

    /// Reveal and select a paper requested from outside the window (e.g. the
    /// menu bar's "Open in VellumX"). Switches to a sidebar tab that contains
    /// the paper so the list selection lands, then opens its detail.
    private func focusRequestedPaper() {
        guard let id = windowOpener.requestedPaperId,
              let paper = store.papers.first(where: { $0.id == id }) else { return }

        selectedTopic = nil
        selectedFields = []
        selectedTiers = []
        searchKeyword = ""

        // If the paper belongs to any collection, switch to the first one.
        if let firstCollectionId = paper.collectionIds.first,
           store.allCollections.contains(where: { $0.id == firstCollectionId }) {
            selectedCollectionId = firstCollectionId
            selectedSidebarItem = nil
        } else {
            selectedCollectionId = nil
            selectedSidebarItem = sidebarItem(for: paper)
        }

        applyFilters()
        selectedPaperId = id
        lastViewedPaperId = id
        windowOpener.requestedPaperId = nil
    }

    private func sidebarItem(for paper: Paper) -> SidebarItem {
        if paper.isRecommended,
           let recommendedAt = paper.recommendedAt,
           Calendar.current.isDateInToday(recommendedAt) {
            return .recommended
        }

        switch paper.status {
        case .pending:  return .pending
        case .starred:  return .starred
        case .read:     return .read
        case .skip:     return .skipped
        }
    }

    // MARK: - Filtering

    private func applyFilters() {
        var result = store.papers

        // 0. Collection view takes priority over sidebar status
        if let collectionId = selectedCollectionId {
            result = result.filter { $0.collectionIds.contains(collectionId) }
        }

        // 1. Filter by Sidebar selection
        else if let selected = selectedSidebarItem {
            switch selected {
            case .all:
                break
            case .recommended:
                result = result.filter { $0.isRecommended }
            case .pending:
                result = result.filter { $0.status == .pending }
            case .starred:
                result = result.filter { $0.status == .starred }
            case .read:
                result = result.filter { $0.status == .read }
            case .skipped:
                result = result.filter { $0.status == .skip }
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
                selectedFields.contains(metadata.field(forAbbr: paper.venueAbbr))
            }
        }
        if !selectedTiers.isEmpty {
            result = result.filter { selectedTiers.contains($0.tier) }
        }
        if !includedTags.isEmpty {
            result = result.filter { paper in
                !includedTags.isDisjoint(with: Set(paper.tags))
            }
        }
        if !excludedTags.isEmpty {
            result = result.filter { paper in
                excludedTags.isDisjoint(with: Set(paper.tags))
            }
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
        } else if selectedSidebarItem == .recommended {
            // Recommend: today first, then history by recommendation date (newest first)
            result.sort {
                let lhsToday = $0.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
                let rhsToday = $1.recommendedAt.map { Calendar.current.isDateInToday($0) } ?? false
                if lhsToday && !rhsToday { return true }
                if !lhsToday && rhsToday { return false }
                return ($0.recommendedAt ?? Date.distantPast) > ($1.recommendedAt ?? Date.distantPast)
            }
        } else {
            result.sort { $0.publicationDate > $1.publicationDate }
        }

        filteredPapers = result
    }

    private func selectPaper(at index: Int) {
        guard filteredPapers.indices.contains(index) else { return }
        let id = filteredPapers[index].id
        selectedPaperId = id
        lastViewedPaperId = id
    }

    private func selectPreviousPaper() {
        guard let index = selectedPaperIndex, index > 0 else { return }
        selectPaper(at: index - 1)
    }

    private func selectNextPaper() {
        guard let index = selectedPaperIndex, index < filteredPapers.count - 1 else { return }
        selectPaper(at: index + 1)
    }

    // MARK: - Actions

    private func updatePaperStatus(_ paper: Paper, status: PaperStatus) {
        let oldIndex = selectedPaperIndex
        let nextId = oldIndex.flatMap { index in
            filteredPapers.indices.contains(index + 1) ? filteredPapers[index + 1].id : nil
        }
        let shouldAdvance = statusListItem(selectedSidebarItem) != nil

        PaperStore.shared.setPaperStatus(id: paper.id, status: status)

        guard shouldAdvance,
              let selectedSidebarItem,
              !paperMatches(sidebarItem: selectedSidebarItem, status: status) else { return }

        applyFilters()
        if let nextId, filteredPapers.contains(where: { $0.id == nextId }) {
            selectedPaperId = nextId
            lastViewedPaperId = nextId
        } else {
            selectedPaperId = nil
            lastViewedPaperId = nil
        }
    }

    private func statusListItem(_ item: SidebarItem?) -> PaperStatus? {
        switch item {
        case .pending: return .pending
        case .starred: return .starred
        case .read: return .read
        case .skipped: return .skip
        default: return nil
        }
    }

    private func paperMatches(sidebarItem: SidebarItem, status: PaperStatus) -> Bool {
        statusListItem(sidebarItem) == status
    }

    private func cancelRecommendation(_ paper: Paper) {
        store.setPaperRecommended(id: paper.id, isRecommended: false)
        applyFilters()
    }

    private func addPaperTag(_ paper: Paper, tag: String) {
        store.addPaperTag(id: paper.id, tag: tag)
        applyFilters()
    }

    private func removePaperTag(_ paper: Paper, tag: String) {
        store.removePaperTag(id: paper.id, tag: tag)
        applyFilters()
    }

    private func addPaperToCollection(_ paper: Paper, collectionId: String) {
        store.addPaperToCollection(paperId: paper.id, collectionId: collectionId)
        applyFilters()
    }

    private func removePaperFromCollection(_ paper: Paper, collectionId: String) {
        store.removePaperFromCollection(paperId: paper.id, collectionId: collectionId)
        applyFilters()
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
                let fetcher = OpenAlexFetcher(config: config, venues: metadata.venues)
                let result = try await fetcher.fetch()
                let stats = store.addOrUpdate(papers: result.papers)
                statusMessage = fetchStatusMessage(
                    inserted: stats.inserted,
                    updated: stats.updated,
                    failedTracks: result.failedTracks
                )
            } catch {
                statusMessage = "Fetch failed: \(error.localizedDescription)"
            }
            isFetching = false
        }
    }

    private func fetchStatusMessage(inserted: Int, updated: Int, failedTracks: [String]) -> String {
        let base = "Fetched! Added \(inserted) | Updated \(updated)"
        guard !failedTracks.isEmpty else { return base }
        return "\(base) | Failed: \(failedTracks.joined(separator: ", "))"
    }

    private func recommendPapers() {
        let config = ConfigManager.shared.effectiveConfig
        isRecommending = true
        statusMessage = "Running recommendation engine..."

        Task {
            let engine = RecommendEngine(config: config)
            let (selected, resetIds) = engine.recommend(papers: store.papers)
            for id in resetIds {
                store.setPaperRecommended(id: id, isRecommended: false)
            }
            for r in selected {
                store.setPaperRecommended(id: r.paper.id, isRecommended: true, reason: r.reason)
            }
            statusMessage = "Selected \(selected.count) recommendations for today!"
            isRecommending = false
        }
    }

    private func translate(paper: Paper) {
        guard settings.translateEnabled else {
            statusMessage = "Translation is disabled — enable it in Settings ▸ API"
            return
        }
        guard !paper.abstract.isEmpty else {
            statusMessage = "No abstract available to translate"
            return
        }
        isTranslating = true
        let provider = ConfigManager.shared.effectiveConfig.translate.provider
        statusMessage = "Translating abstract via \(provider.displayName)..."
        let config = ConfigManager.shared.effectiveConfig

        Task {
            do {
                let translator = TranslationService(config: config, apiKey: settings.apiKey)
                let abstractZh = try await translator.translateAbstract(
                    id: paper.id,
                    abstract: paper.abstract,
                    cachedAbstractZh: paper.abstractZh
                )
                paper.abstractZh = abstractZh
                PaperStore.shared.setPaperTranslation(id: paper.id, abstractZh: abstractZh)
                statusMessage = "Abstract translated successfully!"
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
        let config = ConfigManager.shared.effectiveConfig

        Task {
            let resolver = PdfResolver(config: config)
            if let result = await resolver.resolve(id: paper.id, title: paper.title, doi: paper.doi, currentPdfUrl: paper.pdfUrl),
               let url = URL(string: result.url) {
                paper.pdfUrl = result.url
                store.setPaperPdf(id: paper.id, pdfUrl: result.url, pdfSource: result.source)
                statusMessage = "PDF resolved!"
                NSWorkspace.shared.open(url)
            } else {
                statusMessage = "Could not resolve PDF for this paper"
            }
            isResolvingPdf = false
        }
    }
}

// MARK: - Score Badge (extracted to avoid type-checker timeout)

struct ScoreBadgeView: View {
    let score: Double
    let color: Color

    var body: some View {
        Text(String(format: "%.0f", score))
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
    }
}
