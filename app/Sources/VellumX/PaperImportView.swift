import SwiftUI

/// Sheet for adding a paper to the library manually — either by looking it up
/// on OpenAlex (DOI or title) or by entering metadata by hand.
struct PaperImportView: View {
    let onAdd: (Paper) -> Void

    @Environment(\.dismiss) private var dismiss

    enum Mode { case search, manual }
    @State private var mode: Mode = .search

    // Search state
    @State private var searchInput = ""
    @State private var searchState: SearchState = .idle
    @State private var searchResults: [Paper] = []
    @State private var selectedPaper: Paper?
    @State private var isSearching = false

    // Manual entry state
    @State private var manualTitle = ""
    @State private var manualAuthors = ""
    @State private var manualYear = ""
    @State private var manualVenue = ""
    @State private var manualDOI = ""
    @State private var manualURL = ""

    enum SearchState { case idle, searching, results, notFound, error(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker("", selection: $mode) {
                Text("Search").tag(Mode.search)
                Text("Manual").tag(Mode.manual)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if mode == .search {
                searchPanel
            } else {
                manualPanel
            }
        }
        .frame(width: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Add Paper")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Search panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DOI OR TITLE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.75))
                HStack(spacing: 8) {
                    TextField("e.g. 10.1038/nature12373 or paper title…", text: $searchInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }
                    Button("Search") { performSearch() }
                        .disabled(searchInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
            }

            searchBody

            Spacer()

            HStack {
                if case .results = searchState {
                    Button("Add to Library") { addSelected() }
                        .disabled(selectedPaper == nil)
                        .keyboardShortcut(.defaultAction)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var searchBody: some View {
        switch searchState {
        case .idle:
            EmptyView()
        case .searching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Searching OpenAlex…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .results:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(searchResults) { paper in
                    SearchResultRow(paper: paper, isSelected: selectedPaper?.id == paper.id) {
                        selectedPaper = (selectedPaper?.id == paper.id) ? nil : paper
                    }
                }
            }
        case .notFound:
            VStack(alignment: .leading, spacing: 6) {
                Label("No results found on OpenAlex.", systemImage: "magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Switch to Manual Entry") { mode = .manual }
                    .font(.callout)
            }
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.red.opacity(0.85))
        }
    }

    // MARK: - Manual panel

    private var manualPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            manualField("Title *", placeholder: "Paper title", text: $manualTitle)
            manualField("Authors", placeholder: "Author A, Author B, …", text: $manualAuthors)
            HStack(spacing: 12) {
                manualField("Year", placeholder: "2024", text: $manualYear)
                    .frame(maxWidth: 90)
                manualField("Venue", placeholder: "Conference or journal", text: $manualVenue)
            }
            manualField("DOI", placeholder: "10.xxxx/…", text: $manualDOI)
            manualField("URL", placeholder: "https://…", text: $manualURL)

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add to Library") { addManual() }
                    .disabled(manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func manualField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.75))
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Actions

    private func performSearch() {
        let query = searchInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        selectedPaper = nil
        searchResults = []
        isSearching = true
        searchState = .searching

        let isDOI = query.hasPrefix("10.") || query.contains("doi.org")
        let fetcher = OpenAlexFetcher(
            config: ConfigManager.shared.effectiveConfig,
            venues: MetadataStore.shared.venues
        )

        Task {
            if isDOI {
                let result = await fetcher.fetchByDOI(query)
                await MainActor.run {
                    if let paper = result {
                        searchResults = [paper]
                        searchState = .results
                    } else {
                        searchState = .notFound
                    }
                    isSearching = false
                }
            } else {
                let results = await fetcher.fetchByTitle(query, limit: 5)
                await MainActor.run {
                    if results.isEmpty {
                        searchState = .notFound
                    } else {
                        searchResults = results
                        searchState = .results
                    }
                    isSearching = false
                }
            }
        }
    }

    private func addSelected() {
        guard let paper = selectedPaper else { return }
        onAdd(paper)
        dismiss()
    }

    private func addManual() {
        let title = manualTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let authors = manualAuthors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let doi = manualDOI.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = manualURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(manualYear.trimmingCharacters(in: .whitespacesAndNewlines))
        let venue = manualVenue.trimmingCharacters(in: .whitespacesAndNewlines)

        let paper = Paper(
            id: UUID().uuidString,
            doi: doi.isEmpty ? nil : doi,
            title: title,
            authors: authors,
            publicationDate: year.map { "\($0)" } ?? "",
            publicationYear: year,
            venue: venue,
            landingPageUrl: url.isEmpty ? "" : url,
            addedAt: Date()
        )
        onAdd(paper)
        dismiss()
    }
}

// MARK: - Result row

private struct SearchResultRow: View {
    let paper: Paper
    let isSelected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text(paper.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if !paper.authors.isEmpty {
                        Text(paper.authors.prefix(3).joined(separator: ", "))
                            .lineLimit(1)
                    }
                    if !paper.venue.isEmpty {
                        Text("·")
                        Text(paper.venue)
                            .lineLimit(1)
                    }
                    if !paper.publicationDate.isEmpty {
                        Text("·")
                        Text(paper.publicationDate.prefix(4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.14)
                          : (hovering ? Color.secondary.opacity(0.08) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
