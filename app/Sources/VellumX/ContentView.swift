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
    /// Debounced mirror of `searchKeyword` — drives the actual filtering so a
    /// burst of keystrokes triggers at most one `applyFilters` pass.
    @State private var debouncedSearch: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
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
    /// Multi-selection of paper IDs (⌘/⇧ click). count==1 drives the detail view.
    @State private var selectedPaperIds: Set<String> = []
    /// Last paper actually opened; retained when the list selection clears.
    @State private var lastViewedPaperId: String?
    /// Bumped by the Add Tag command to ask the detail view to open its prompt.
    @State private var addTagSignal: Int = 0

    // Async execution states
    @State private var isFetching: Bool = false
    @State private var isRecommending: Bool = false
    @State private var isTranslating: Bool = false
    @State private var isResolvingPdf: Bool = false

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
            search: debouncedSearch,
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

    /// Papers currently multi-selected, in list order.
    private var selectedPapers: [Paper] {
        filteredPapers.filter { selectedPaperIds.contains($0.id) }
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
                papers: store.papers
            )
        } content: {
            PaperListView(
                papers: filteredPapers,
                selectedPaperIds: $selectedPaperIds,
                metadata: metadata,
                highlightsDailyRecommendations: selectedSidebarItem == .recommended && selectedCollectionId == nil,
                onCancelRecommendation: cancelRecommendation,
                onSelectionChange: handleSelectionChange,
                onCopyBibtex: copyBibtex,
                onUpdatePaper: updatePaper,
                onDeletePaper: confirmDelete,
                onSetStatus: setStatus,
                onAddToCollection: addToCollection,
                collections: store.allCollections
            )
        } detail: {
            if selectedPaperIds.count > 1 {
                BatchActionsView(
                    papers: selectedPapers,
                    collections: store.allCollections,
                    onCopyBibtex: { copyBibtex(selectedPapers) },
                    onSetStatus: { setStatus(selectedPapers, $0) },
                    onAddToCollection: { addToCollection(selectedPapers, $0) },
                    onAddTag: { requestAddTag(selectedPapers) },
                    onUpdate: { updatePaper(selectedPapers) },
                    onDelete: { confirmDelete(selectedPapers) }
                )
            } else if let paper = selectedPaper {
                PaperDetailView(
                    paper: paper,
                    isTranslating: $isTranslating,
                    isResolvingPdf: $isResolvingPdf,
                    onTranslate: translate,
                    onResolvePdf: resolvePdf,
                    onStatusChange: updatePaperStatus,
                    onAddTag: addPaperTag,
                    onRemoveTag: removePaperTag,
                    onAddToCollection: addPaperToCollection,
                    onRemoveFromCollection: removePaperFromCollection,
                    addTagSignal: addTagSignal
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
        .onChange(of: searchKeyword) { _, new in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
                debouncedSearch = new
            }
        }
        .onChange(of: windowOpener.requestedPaperId) { focusRequestedPaper() }
        .onChange(of: selectedSidebarItem) { _, new in
            if new != nil { selectedCollectionId = nil }
        }
        .searchable(text: $searchKeyword, placement: .toolbar, prompt: "Search title, abstract or authors...")
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
        // Publish the runnable actions to the menu-bar commands (AppCommands).
        .focusedSceneValue(\.paperActions, paperActions)
    }

    /// Snapshot of menu-bar command actions for the current state. Optional
    /// closures encode disabled state; `selectedSidebarItem`'s own `.onChange`
    /// clears the collection selection. Kept out of `body` so the type-checker
    /// doesn't have to solve these closures inside the view tree.
    private var paperActions: PaperActions {
        let busy = isFetching || isRecommending
        let selectView: (SidebarItem) -> Void = { selectedSidebarItem = $0 }
        let selectPrevious: (() -> Void)? = canGoPrevious ? { selectPreviousPaper() } : nil
        let selectNext: (() -> Void)? = canGoNext ? { selectNextPaper() } : nil
        let setStatus: ((PaperStatus) -> Void)? = selectedPaper.map { paper in
            { updatePaperStatus(paper, status: $0) }
        }
        let addTag: (() -> Void)? = selectedPaper == nil ? nil : { addTagSignal += 1 }
        let fetch: (() -> Void)? = busy ? nil : { fetchPapers() }
        let recommend: (() -> Void)? = busy ? nil : { recommendPapers() }
        return PaperActions(
            selectView: selectView,
            selectPrevious: selectPrevious,
            selectNext: selectNext,
            setStatus: setStatus,
            addTag: addTag,
            fetch: fetch,
            recommend: recommend
        )
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
        debouncedSearch = ""

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
        selectedPaperIds = [id]
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

        // 0. Collection view takes priority over sidebar status. A parent folder
        //    stands in for its whole subtree, so include descendants' papers too.
        if let collectionId = selectedCollectionId {
            let subtree = store.collectionSubtreeIds(collectionId)
            result = result.filter { paper in paper.collectionIds.contains(where: subtree.contains) }
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

        // 2. Filter by search keyword. Tokens are AND-matched against each
        // paper's cached lowercased `searchText` (title, abstract, authors,
        // venue, tags, note) — no per-keystroke re-lowercasing of abstracts.
        let tokens = debouncedSearch.lowercased().split(separator: " ").map(String.init)
        if !tokens.isEmpty {
            result = result.filter { paper in
                let hay = paper.searchText
                return tokens.allSatisfy { hay.contains($0) }
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
        selectedPaperIds = [id]
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
            selectedPaperIds = [nextId]
            lastViewedPaperId = nextId
        } else {
            selectedPaperIds = []
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

    /// When exactly one row is selected, open it in the detail pane. Multi- or
    /// zero-selection leaves `lastViewedPaperId` so the detail pane can show the
    /// batch placeholder or keep the last opened paper.
    private func handleSelectionChange(_ ids: Set<String>) {
        if ids.count == 1, let id = ids.first {
            lastViewedPaperId = id
        }
    }

    private func copyBibtex(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(CitationExporter.bibtex(for: papers), forType: .string)
        NotificationCenter.shared.showToast(
            papers.count == 1
                ? L10n.t(.copiedBibtex)
                : "Copied \(papers.count) BibTeX entries",
            type: .success
        )
    }

    private func confirmDelete(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let title = papers.count == 1
            ? L10n.t(.deleteConfirmTitle)
            : (AppSettings.shared.language == "zh"
                ? "删除选中的 \(papers.count) 篇论文？"
                : "Delete \(papers.count) papers?")
        NotificationCenter.shared.present(AlertItem(
            title: title,
            message: L10n.t(.deleteConfirmMessage),
            actions: [
                .confirm(L10n.t(.delete), isDestructive: true, action: { deletePapers(papers) }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: nil, textFieldLabel: nil
        ))
    }

    private func deletePapers(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        let ids = Set(papers.map(\.id))
        let removedOpen = lastViewedPaperId.map(ids.contains) ?? false
        store.deletePapers(ids: Array(ids))
        selectedPaperIds.subtract(ids)
        applyFilters()
        if removedOpen { lastViewedPaperId = nil }
    }

    /// Refresh papers' metadata from OpenAlex, keeping all user state.
    private func updatePaper(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        // Preserve each paper's track: fetchWorksByIds parses with track "",
        // and addOrUpdate's replaceTopics would otherwise wipe their topics.
        let trackById = Dictionary(papers.map { ($0.id, $0.track) }, uniquingKeysWith: { a, _ in a })
        NotificationCenter.shared.setStatus(
            papers.count == 1
                ? "Updating from OpenAlex..."
                : "Updating \(papers.count) papers from OpenAlex...",
            type: .progress
        )

        Task {
            let fetcher = OpenAlexFetcher(
                config: ConfigManager.shared.effectiveConfig,
                venues: metadata.venues
            )
            let refreshed = await fetcher.fetchWorksByIds(papers.map(\.id))
            guard !refreshed.isEmpty else {
                NotificationCenter.shared.setStatus("Update failed — no result from OpenAlex.", type: .error)
                return
            }
            for r in refreshed { r.track = trackById[r.id] ?? r.track }
            _ = store.addOrUpdate(papers: refreshed)
            applyFilters()
            NotificationCenter.shared.showToast(
                refreshed.count == 1
                    ? "Updated \"\(refreshed[0].title)\""
                    : "Updated \(refreshed.count) papers",
                type: .success
            )
            NotificationCenter.shared.clearStatus()
        }
    }

    // MARK: - Batch actions (operate on a set of papers)

    private func setStatus(_ papers: [Paper], _ status: PaperStatus) {
        for paper in papers { store.setPaperStatus(id: paper.id, status: status) }
        applyFilters()
    }

    private func addToCollection(_ papers: [Paper], _ collectionId: String) {
        for paper in papers { store.addPaperToCollection(paperId: paper.id, collectionId: collectionId) }
        applyFilters()
    }

    private func addTag(_ papers: [Paper], _ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for paper in papers { store.addPaperTag(id: paper.id, tag: trimmed) }
        applyFilters()
    }

    private func requestAddTag(_ papers: [Paper]) {
        guard !papers.isEmpty else { return }
        NotificationCenter.shared.present(AlertItem(
            title: L10n.t(.cmdAddTag),
            message: nil,
            actions: [
                .confirm(L10n.t(.cmdAddTag), action: {
                    let tag = NotificationCenter.shared.currentAlert?.textFieldValue ?? ""
                    addTag(papers, tag)
                }),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: "",
            textFieldLabel: "Tag"
        ))
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
        guard !ConfigManager.shared.effectiveConfig.tracks.isEmpty else {
            NotificationCenter.shared.setStatus("No tracks configured — add one in Settings ▸ Papers", type: .error)
            return
        }
        // Fetching contacts OpenAlex and can be slow; confirm before running.
        NotificationCenter.shared.present(AlertItem(
            title: L10n.t(.fetchConfirmTitle),
            message: L10n.t(.fetchConfirmMessage),
            actions: [
                .confirm(L10n.t(.cmdFetch), action: performFetch),
                .cancel(L10n.t(.cancel))
            ],
            textFieldValue: nil, textFieldLabel: nil
        ))
    }

    private func performFetch() {
        let config = ConfigManager.shared.effectiveConfig
        isFetching = true
        NotificationCenter.shared.setStatus("Fetching OpenAlex papers...", type: .progress)

        Task {
            do {
                let fetcher = OpenAlexFetcher(config: config, venues: metadata.venues)
                let result = try await fetcher.fetch()
                let stats = store.addOrUpdate(papers: result.papers)
                let msg = fetchStatusMessage(
                    inserted: stats.inserted,
                    updated: stats.updated,
                    failedTracks: result.failedTracks
                )
                NotificationCenter.shared.showToast(msg, type: .success)
                NotificationCenter.shared.clearStatus()
            } catch {
                NotificationCenter.shared.showToast("Fetch failed: \(error.localizedDescription)", type: .error)
                NotificationCenter.shared.clearStatus()
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
        NotificationCenter.shared.setStatus("Running recommendation engine...", type: .progress)

        Task {
            let engine = RecommendEngine(config: config)
            let selected = engine.recommend(papers: store.papers)
            for r in selected {
                store.setPaperRecommended(id: r.paper.id, isRecommended: true, reason: r.reason)
            }
            NotificationCenter.shared.showToast(
                selected.isEmpty
                    ? "No new candidates to recommend."
                    : "Added \(selected.count) new recommendations!",
                type: selected.isEmpty ? .info : .success
            )
            NotificationCenter.shared.clearStatus()
            isRecommending = false
        }
    }

    private func translate(paper: Paper) {
        guard settings.translateEnabled else {
            NotificationCenter.shared.showToast("Translation is disabled — enable it in Settings ▸ API", type: .warning)
            return
        }
        guard !paper.abstract.isEmpty else {
            NotificationCenter.shared.showToast("No abstract available to translate", type: .warning)
            return
        }
        isTranslating = true
        let provider = ConfigManager.shared.effectiveConfig.translate.provider
        NotificationCenter.shared.setStatus("Translating abstract via \(provider.displayName)...", type: .progress)
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
                NotificationCenter.shared.showToast("Abstract translated successfully!", type: .success)
                NotificationCenter.shared.clearStatus()
            } catch {
                NotificationCenter.shared.showToast("Translation failed: \(error.localizedDescription)", type: .error)
                NotificationCenter.shared.clearStatus()
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
        NotificationCenter.shared.setStatus("Resolving OpenAccess PDF...", type: .progress)
        let config = ConfigManager.shared.effectiveConfig

        Task {
            let resolver = PdfResolver(config: config)
            if let result = await resolver.resolve(id: paper.id, title: paper.title, doi: paper.doi, currentPdfUrl: paper.pdfUrl),
               let url = URL(string: result.url) {
                paper.pdfUrl = result.url
                store.setPaperPdf(id: paper.id, pdfUrl: result.url, pdfSource: result.source)
                NotificationCenter.shared.showToast("PDF resolved!", type: .success)
                NotificationCenter.shared.clearStatus()
                NSWorkspace.shared.open(url)
            } else {
                NotificationCenter.shared.showToast("Could not resolve PDF for this paper", type: .error)
                NotificationCenter.shared.clearStatus()
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
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Batch actions panel (shown when >1 paper is selected)

private struct BatchActionsView: View {
    let papers: [Paper]
    let collections: [PaperCollection]
    let onCopyBibtex: () -> Void
    let onSetStatus: (PaperStatus) -> Void
    let onAddToCollection: (String) -> Void
    let onAddTag: () -> Void
    let onUpdate: () -> Void
    let onDelete: () -> Void

    @State private var showStatus = false
    @State private var showCollection = false

    private let panelWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            header
            actions
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 56, height: 56)
                Image(systemName: "checklist")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            Text("\(papers.count) \(L10n.t(.batchSelected))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            pillButton(L10n.t(.cite), "doc.on.doc", action: onCopyBibtex)

            pillButton(L10n.t(.cmdSetStatus), "flag", chevron: true) { showStatus = true }
                .popover(isPresented: $showStatus, arrowEdge: .trailing) {
                    popoverList {
                        ForEach(PaperStatus.allCases, id: \.self) { status in
                            popoverRow(status.displayName, status.iconName) {
                                onSetStatus(status)
                                showStatus = false
                            }
                        }
                    }
                }

            if !collections.isEmpty {
                pillButton(L10n.t(.cmdAddToCollection), "folder", chevron: true) { showCollection = true }
                    .popover(isPresented: $showCollection, arrowEdge: .trailing) {
                        popoverList {
                            ForEach(collections) { collection in
                                popoverRow(collection.name, collection.icon ?? "folder") {
                                    onAddToCollection(collection.id)
                                    showCollection = false
                                }
                            }
                        }
                    }
            }

            pillButton(L10n.t(.cmdAddTag), "tag", action: onAddTag)
            pillButton(L10n.t(.cmdUpdatePaper), "arrow.clockwise", action: onUpdate)

            Divider().padding(.vertical, 4)

            pillButton(L10n.t(.cmdDeletePaper), "trash", role: .destructive, action: onDelete)
        }
        .frame(width: panelWidth)
    }

    private func pillButton(_ title: String, _ icon: String,
                            role: ButtonRole? = nil,
                            chevron: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .overlay(alignment: .trailing) {
                    if chevron {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .buttonStyle(BatchPillButtonStyle(destructive: role == .destructive))
    }

    private func popoverList<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) { content() }
            .padding(6)
            .frame(minWidth: 170)
    }

    private func popoverRow(_ title: String, _ icon: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Full-width pill button used in the batch actions panel, with hover and
/// pressed feedback so every row (including the popover triggers) matches.
private struct BatchPillButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        Pill(configuration: configuration, destructive: destructive)
    }

    private struct Pill: View {
        let configuration: ButtonStyle.Configuration
        let destructive: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(destructive ? Color.red : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(
                            configuration.isPressed ? 0.16 : (hovering ? 0.11 : 0.07)
                        ))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onHover { hovering = $0 }
        }
    }
}
