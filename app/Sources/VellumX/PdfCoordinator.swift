import Foundation

/// UI-facing bridge for PDF actions. Keeps the two user intents separate —
/// *fetching* a PDF and *revealing* an already-downloaded one — and owns the
/// app-state side effects (persistence + toasts) that the pure `PdfFetcher`
/// deliberately avoids.
@MainActor
enum PdfCoordinator {

    /// True when the paper has a validated PDF stored on disk.
    static func hasLocalPdf(_ paper: Paper) -> Bool {
        guard let path = paper.pdfLocalPath, !path.isEmpty else { return false }
        return PdfStorage.current().fileExists(relative: path)
    }

    /// Resolves and downloads a PDF, persists the outcome, and reports it via a
    /// toast. Does not open anything — fetching and opening are distinct actions.
    static func fetch(paper: Paper, store: PaperStore) async {
        let storage = PdfStorage.current()
        let config = ConfigManager.shared.effectiveConfig

        NotificationCenter.shared.setStatus(L10n.t(.resolvingPDF), type: .progress)
        let result = await PdfFetcher(config: config, storage: storage)
            .fetch(id: paper.id, title: paper.title, doi: paper.doi, currentPdfUrl: paper.pdfUrl)
        store.savePdf(id: paper.id, result: result)
        NotificationCenter.shared.clearStatus()

        switch result.status {
        case .downloaded:
            NotificationCenter.shared.showToast(L10n.t(.pdfDownloaded), type: .success)
        case .notPdf:
            NotificationCenter.shared.showToast(L10n.t(.pdfNotAvailable), type: .warning)
        case .dead, .resolved:
            NotificationCenter.shared.showToast(L10n.t(.pdfNotFound), type: .error)
        }
    }

    /// Reveals the downloaded PDF in Finder with it selected. If the file is
    /// missing (e.g. deleted out of band), re-fetches it instead.
    static func reveal(paper: Paper, store: PaperStore) async {
        if let path = paper.pdfLocalPath, PdfStorage.current().revealInFinder(relative: path) {
            return
        }
        await fetch(paper: paper, store: store)
    }
}
