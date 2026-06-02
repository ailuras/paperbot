import Foundation

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
    
    func resolve(id: String, title: String, doi: String?, currentPdfUrl: String?) async -> (url: String, source: String)? {
        if let currentPdf = currentPdfUrl, !currentPdf.isEmpty {
            return (currentPdf, "cached")
        }

        guard let rawDoi = doi, !rawDoi.isEmpty else {
            if let arxivPdf = await fetchArxiv(title: title) {
                return (arxivPdf, "arxiv")
            }
            return nil
        }

        // OpenAlex returns DOIs as full URLs (https://doi.org/10.xxx).
        // Unpaywall and Semantic Scholar expect a bare DOI path (10.xxx).
        let bareDoi = Self.stripDoiPrefix(rawDoi)

        if let unpaywallPdf = await fetchUnpaywall(doi: bareDoi) {
            return (unpaywallPdf, "unpaywall")
        }

        if let arxivPdf = await fetchArxiv(title: title) {
            return (arxivPdf, "arxiv")
        }

        if let s2Pdf = await fetchSemanticScholar(doi: bareDoi) {
            return (s2Pdf, "semanticscholar")
        }

        return nil
    }

    private static func stripDoiPrefix(_ doi: String) -> String {
        let lower = doi.lowercased()
        for prefix in ["https://doi.org/", "http://doi.org/",
                        "https://dx.doi.org/", "http://dx.doi.org/"] {
            if lower.hasPrefix(prefix) { return String(doi.dropFirst(prefix.count)) }
        }
        return doi
    }
}
