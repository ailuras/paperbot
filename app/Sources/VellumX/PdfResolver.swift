import Foundation

@MainActor
class PdfResolver {
    let config: AppConfig
    
    init(config: AppConfig = ConfigManager.shared.effectiveConfig) {
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
        var components = URLComponents(string: "http://export.arxiv.org/api/query")
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
        let key = config.semantic_scholar_key ?? ""
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/DOI:\(doi)")
        components?.queryItems = [URLQueryItem(name: "fields", value: "openAccessPdf")]
        
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        if !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
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
    
    func resolve(paper: Paper) async -> String? {
        // Cache / Preset check
        if let currentPdf = paper.pdfUrl, !currentPdf.isEmpty {
            return currentPdf
        }
        
        guard let doi = paper.doi, !doi.isEmpty else {
            // If no DOI, fallback to arXiv title lookup
            if let arxivPdf = await fetchArxiv(title: paper.title) {
                paper.pdfUrl = arxivPdf
                PaperStore.shared.setPaperPdf(id: paper.id, pdfUrl: arxivPdf, pdfSource: "arxiv")
                return arxivPdf
            }
            return nil
        }
        
        // Layer 2: Unpaywall
        if let unpaywallPdf = await fetchUnpaywall(doi: doi) {
            paper.pdfUrl = unpaywallPdf
            PaperStore.shared.setPaperPdf(id: paper.id, pdfUrl: unpaywallPdf, pdfSource: "unpaywall")
            return unpaywallPdf
        }
        
        // Layer 3: arXiv
        if let arxivPdf = await fetchArxiv(title: paper.title) {
            paper.pdfUrl = arxivPdf
            PaperStore.shared.setPaperPdf(id: paper.id, pdfUrl: arxivPdf, pdfSource: "arxiv")
            return arxivPdf
        }
        
        // Layer 4: Semantic Scholar
        if let s2Pdf = await fetchSemanticScholar(doi: doi) {
            paper.pdfUrl = s2Pdf
            PaperStore.shared.setPaperPdf(id: paper.id, pdfUrl: s2Pdf, pdfSource: "semanticscholar")
            return s2Pdf
        }
        
        return nil
    }
}
