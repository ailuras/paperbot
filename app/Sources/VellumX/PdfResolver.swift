import Foundation
import AppKit

class PdfResolver {
    let config: AppConfig
    
    init(config: AppConfig) {
        self.config = config
    }
    
    private func fetchUnpaywall(doi: String) async -> String? {
        let email = config.openalex.mailto
        if email.isEmpty { return nil }
        
        var components = URLComponents(string: "https://api.unpaywall.org/v2/\(doi)")
        components?.queryItems = [URLQueryItem(name: "email", value: email)]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            // Decodable DTO for Unpaywall
            struct UnpaywallLocation: Decodable {
                var url_for_pdf: String?
                var url: String?
            }
            struct UnpaywallResponse: Decodable {
                var is_oa: Bool?
                var best_oa_location: UnpaywallLocation?
            }
            
            let result = try JSONDecoder().decode(UnpaywallResponse.self, from: data)
            if result.is_oa == true {
                return result.best_oa_location?.url_for_pdf ?? result.best_oa_location?.url
            }
        } catch {
            print("Unpaywall lookup failed: \(error)")
        }
        return nil
    }
    
    private func fetchArxiv(title: String) async -> String? {
        if title.isEmpty { return nil }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "ti:\"\(title)\""),
            URLQueryItem(name: "max_results", value: "3"),
            URLQueryItem(name: "sortBy", value: "relevance")
        ]
        
        guard let url = components?.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            guard let xmlString = String(data: data, encoding: .utf8) else { return nil }
            
            // Using regex to extract arXiv ID
            let pattern = "<id>http://arxiv.org/abs/(.+?)</id>"
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(location: 0, length: xmlString.utf16.count)
            
            if let match = regex.firstMatch(in: xmlString, options: [], range: range) {
                if let idRange = Range(match.range(at: 1), in: xmlString) {
                    let rawId = String(xmlString[idRange])
                    return "https://arxiv.org/pdf/\(rawId).pdf"
                }
            }
        } catch {
            print("arXiv lookup failed: \(error)")
        }
        return nil
    }
    
    private func fetchSemanticScholar(doi: String) async -> String? {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/DOI:\(doi)")
        components?.queryItems = [URLQueryItem(name: "fields", value: "openAccessPdf")]

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            struct S2OpenAccessPdf: Decodable {
                var url: String?
            }
            struct S2Response: Decodable {
                var openAccessPdf: S2OpenAccessPdf?
            }
            
            let result = try JSONDecoder().decode(S2Response.self, from: data)
            return result.openAccessPdf?.url
        } catch {
            print("Semantic Scholar lookup failed: \(error)")
        }
        return nil
    }
    
    /// Collects every candidate PDF link in priority order. Unlike a
    /// first-non-empty resolver, this returns all sources so the downloader can
    /// validate each in turn and keep the first that is actually a PDF.
    func candidates(title: String, doi: String?, currentPdfUrl: String?) async -> [(url: String, source: String)] {
        var result: [(url: String, source: String)] = []

        if let currentPdf = currentPdfUrl, !currentPdf.isEmpty {
            result.append((currentPdf, "openalex"))
        }

        // OpenAlex returns DOIs as full URLs (https://doi.org/10.xxx).
        // Unpaywall and Semantic Scholar expect a bare DOI path (10.xxx).
        let bareDoi = doi.map(Self.stripDoiPrefix).flatMap { $0.isEmpty ? nil : $0 }

        if let bareDoi, let unpaywallPdf = await fetchUnpaywall(doi: bareDoi) {
            result.append((unpaywallPdf, "unpaywall"))
        }

        if let arxivPdf = await fetchArxiv(title: title) {
            result.append((arxivPdf, "arxiv"))
        }

        if let bareDoi, let s2Pdf = await fetchSemanticScholar(doi: bareDoi) {
            result.append((s2Pdf, "semanticscholar"))
        }

        return result
    }

    static func stripDoiPrefix(_ doi: String) -> String {
        let lower = doi.lowercased()
        for prefix in ["https://doi.org/", "http://doi.org/",
                        "https://dx.doi.org/", "http://dx.doi.org/"] {
            if lower.hasPrefix(prefix) { return String(doi.dropFirst(prefix.count)) }
        }
        return doi
    }
}

/// Resolves candidate links, downloads each until one validates as a real PDF,
/// and stores the bytes locally. Content parsing (full text, in-app reader) is
/// intentionally out of scope for this phase — this only "fetches".
struct PdfFetcher {
    let config: AppConfig
    let storage: PdfStorage

    /// Downloads and validates a paper's PDF. Returns the materialized result;
    /// the caller is responsible for persisting it via `PaperStore.savePdf`.
    func fetch(id: String, title: String, doi: String?, currentPdfUrl: String?) async -> PdfFetchResult {
        let resolver = PdfResolver(config: config)
        let candidates = await resolver.candidates(title: title, doi: doi, currentPdfUrl: currentPdfUrl)
        if candidates.isEmpty { return .dead }

        var firstUrl: String?
        var firstSource: String?
        for candidate in candidates {
            guard let url = URL(string: candidate.url) else { continue }
            if firstUrl == nil { firstUrl = candidate.url; firstSource = candidate.source }
            guard let data = await Self.download(url) else { continue }
            guard PdfStorage.looksLikePdf(data) else { continue }

            do {
                let relative = try storage.write(data, forPaperId: id)
                return PdfFetchResult(
                    status: .downloaded,
                    url: candidate.url,
                    source: candidate.source,
                    localPath: relative,
                    byteSize: data.count,
                    sha256: PdfStorage.sha256Hex(data)
                )
            } catch {
                print("PDF write failed: \(error)")
            }
        }

        // Candidates existed but none was a real PDF (landing page / paywall).
        if let firstUrl, let firstSource {
            return .notPdf(url: firstUrl, source: firstSource)
        }
        return .dead
    }

    /// Shared entry point for both the detail view and the menu bar: opens the
    /// local PDF if already downloaded, otherwise fetches, persists, and opens
    /// the result (falling back to the source link when no PDF could be stored).
    @MainActor
    static func openOrFetch(paper: Paper, store: PaperStore, config: AppConfig) async {
        let storage = PdfStorage.current()

        if let path = paper.pdfLocalPath, !path.isEmpty, storage.fileExists(relative: path) {
            NSWorkspace.shared.open(storage.absoluteURL(forRelative: path))
            return
        }

        NotificationCenter.shared.setStatus("Resolving OpenAccess PDF...", type: .progress)
        let result = await PdfFetcher(config: config, storage: storage)
            .fetch(id: paper.id, title: paper.title, doi: paper.doi, currentPdfUrl: paper.pdfUrl)
        store.savePdf(id: paper.id, result: result)
        NotificationCenter.shared.clearStatus()

        switch result.status {
        case .downloaded:
            if let path = result.localPath {
                NotificationCenter.shared.showToast("PDF downloaded", type: .success)
                NSWorkspace.shared.open(storage.absoluteURL(forRelative: path))
            }
        case .notPdf:
            NotificationCenter.shared.showToast("No downloadable PDF; opened source link", type: .info)
            if let link = result.url, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        case .dead, .resolved:
            NotificationCenter.shared.showToast("No open-access PDF found", type: .error)
        }
    }

    private static func download(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            print("PDF download failed for \(url): \(error)")
            return nil
        }
    }
}
