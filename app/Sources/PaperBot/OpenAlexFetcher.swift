import Foundation

// MARK: - OpenAlex API DTOs

struct OpenAlexSource: Decodable {
    var displayName: String?
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct OpenAlexLocation: Decodable {
    var source: OpenAlexSource?
    var landingPageUrl: String?
    var pdfUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case source
        case landingPageUrl = "landing_page_url"
        case pdfUrl = "pdf_url"
    }
}

struct OpenAlexAuthor: Decodable {
    var displayName: String?
    
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

struct OpenAlexAuthorship: Decodable {
    var author: OpenAlexAuthor?
}

struct OpenAlexOpenAccess: Decodable {
    var oaUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case oaUrl = "oa_url"
    }
}

struct OpenAlexWork: Decodable {
    var id: String
    var doi: String?
    var title: String?
    var displayName: String?
    var authorships: [OpenAlexAuthorship]?
    var publicationYear: Int?
    var publicationDate: String?
    var citedByCount: Int?
    var abstractInvertedIndex: [String: [Int]]?
    var primaryLocation: OpenAlexLocation?
    var openAccess: OpenAlexOpenAccess?
    
    enum CodingKeys: String, CodingKey {
        case id, doi, title, authorships
        case displayName = "display_name"
        case publicationYear = "publication_year"
        case publicationDate = "publication_date"
        case citedByCount = "cited_by_count"
        case abstractInvertedIndex = "abstract_inverted_index"
        case primaryLocation = "primary_location"
        case openAccess = "open_access"
    }
}

struct OpenAlexMeta: Decodable {
    var nextCursor: String?
    
    enum CodingKeys: String, CodingKey {
        case nextCursor = "next_cursor"
    }
}

struct OpenAlexResponse: Decodable {
    var meta: OpenAlexMeta?
    var results: [OpenAlexWork]?
}

// MARK: - Fetcher Class

@MainActor
class OpenAlexFetcher {
    let config: AppConfig
    let scorer: VenueScorer
    
    init(config: AppConfig = ConfigManager.shared.config ?? AppConfig(
        openalex: OpenAlexConfig(base_url: "https://api.openalex.org/works", mailto: "", api_key_env: "OPENALEX_API_KEY", timeout_seconds: 20, per_page: 100, default_days: 45, default_max_results: 1000, topic_filter: "topics.field.id:17"),
        tracks: [:],
        scoring: ScoringConfig(tiers: [:], citation_breakpoints: [], max_citation_points: 40),
        recommendation: RecommendationConfig(daily_count: 3, quality_slots: 1, high_score_threshold: 5, recent_days: 30),
        translate: TranslateConfig(enabled: false, target_language: "中文", model: "", include_in_email: false, api_key_env: "", base_url: ""),
        mail: MailConfig(smtp_host: "", smtp_port: 0, smtp_user: "", smtp_password: "", from_addr: "", to_addrs: [], use_tls: false, dashboard_url: "")
    )) {
        self.config = config
        self.scorer = VenueScorer(config: config)
    }
    
    private func restoreAbstract(from index: [String: [Int]]?) -> String {
        guard let index = index else { return "" }
        var wordsList: [(Int, String)] = []
        for (word, positions) in index {
            for pos in positions {
                wordsList.append((pos, word))
            }
        }
        wordsList.sort { $0.0 < $1.0 }
        return wordsList.map { $0.1 }.joined(separator: " ")
    }
    
    private func isKeywordMatched(text: String, keyword: String) -> Bool {
        let escapedPattern = NSRegularExpression.escapedPattern(for: keyword.lowercased())
        let pattern = "\\b\(escapedPattern)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    private func isRelevant(paper: Paper, trackName: String) -> Bool {
        let titleLower = paper.title.lowercased()
        let text = "\(titleLower) \(paper.abstract.lowercased())"
        
        // 1. Title blacklist check
        if let titleBlacklist = config.filters?.title_blacklist {
            for token in titleBlacklist {
                if titleLower.contains(token.lowercased()) {
                    return false
                }
            }
        }
        
        // 2. Source blacklist check
        if let sourceBlacklist = config.filters?.source_blacklist {
            let venueLower = paper.venue.lowercased()
            for token in sourceBlacklist {
                if venueLower.contains(token.lowercased()) {
                    return false
                }
            }
        }
        
        // 3. Track keywords check
        guard let trackConfig = config.tracks[trackName] else { return false }
        for keyword in trackConfig.keywords {
            if isKeywordMatched(text: text, keyword: keyword) {
                return true
            }
        }
        
        return false
    }
    
    private func searchPapers(
        query: String,
        fromDate: String,
        toDate: String,
        maxResults: Int
    ) async throws -> [OpenAlexWork] {
        var collectedWorks: [OpenAlexWork] = []
        var cursor = "*"
        let baseUrl = config.openalex.base_url
        let perPage = config.openalex.per_page
        let topicFilter = config.openalex.topic_filter
        let mailto = ProcessInfo.processInfo.environment["OPENALEX_MAILTO"] ?? config.openalex.mailto
        let apiKey = ProcessInfo.processInfo.environment[config.openalex.api_key_env] ?? ""
        
        let session = URLSession.shared
        
        while collectedWorks.count < maxResults {
            var filters = [
                "from_publication_date:\(fromDate)",
                "to_publication_date:\(toDate)",
                "type:article"
            ]
            if !topicFilter.isEmpty {
                filters.append(topicFilter)
            }
            
            var components = URLComponents(string: baseUrl)
            var queryItems = [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "filter", value: filters.joined(separator: ",")),
                URLQueryItem(name: "sort", value: "publication_date:desc,relevance_score:desc"),
                URLQueryItem(name: "per_page", value: String(min(perPage, maxResults - collectedWorks.count))),
                URLQueryItem(name: "cursor", value: cursor),
                URLQueryItem(name: "select", value: "id,doi,title,display_name,authorships,publication_year,publication_date,cited_by_count,abstract_inverted_index,primary_location,open_access")
            ]
            
            if !mailto.isEmpty {
                queryItems.append(URLQueryItem(name: "mailto", value: mailto))
            }
            if !apiKey.isEmpty {
                queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            }
            
            components?.queryItems = queryItems
            
            guard let url = components?.url else {
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            var userAgent = "PaperBot/1.0"
            if !mailto.isEmpty {
                userAgent += " (mailto:\(mailto))"
            }
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            
            let decoder = JSONDecoder()
            let alexResponse = try decoder.decode(OpenAlexResponse.self, from: data)
            
            guard let results = alexResponse.results else { break }
            collectedWorks.append(contentsOf: results)
            
            guard let nextCursor = alexResponse.meta?.nextCursor, !results.isEmpty else { break }
            cursor = nextCursor
            
            // Rate limit friendliness
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        return collectedWorks
    }
    
    private func parseWork(_ work: OpenAlexWork, track: String) -> Paper {
        let venue = work.primaryLocation?.source?.displayName ?? ""
        let citations = work.citedByCount ?? 0
        let tier = scorer.getTier(venue: venue)
        let venueAbbr = scorer.computeVenueAbbr(venue: venue)
        
        let authors = work.authorships?.compactMap { $0.author?.displayName } ?? []
        let abstract = restoreAbstract(from: work.abstractInvertedIndex)
        
        let landingPage = work.primaryLocation?.landingPageUrl ?? work.doi ?? work.id
        let pdf = work.primaryLocation?.pdfUrl ?? work.openAccess?.oaUrl
        
        let score = scorer.calculateScore(venue: venue, citations: citations)
        
        return Paper(
            id: work.id,
            doi: work.doi,
            title: work.displayName ?? work.title ?? "",
            authors: authors,
            publicationDate: work.publicationDate ?? "",
            publicationYear: work.publicationYear,
            venue: venue,
            venueAbbr: venueAbbr,
            citedByCount: citations,
            abstract: abstract,
            landingPageUrl: landingPage,
            pdfUrl: pdf,
            track: track,
            score: score,
            tier: tier
        )
    }
    
    private func dedupeAndMergeTracks(papers: [Paper]) -> [Paper] {
        var byId: [String: Paper] = [:]
        for paper in papers {
            let pid = paper.id
            if pid.isEmpty { continue }
            
            if let existing = byId[pid] {
                // Combine tracks
                let existingTracks = existing.track.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                var trackSet = Set(existingTracks)
                if !paper.track.isEmpty {
                    trackSet.insert(paper.track)
                }
                existing.track = trackSet.sorted().joined(separator: ",")
                existing.score = max(existing.score, paper.score)
            } else {
                byId[pid] = paper
            }
        }
        return Array(byId.values)
    }
    
    func fetch(days: Int? = nil, maxResults: Int? = nil) async throws -> (papers: [Paper], totalRaw: Int, totalFiltered: Int) {
        let daysToFetch = days ?? config.openalex.default_days
        let resultsCap = maxResults ?? config.openalex.default_max_results
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let today = Date()
        guard let fromDay = Calendar.current.date(byAdding: .day, value: -(daysToFetch - 1), to: today) else {
            throw URLError(.cannotParseResponse)
        }
        
        let fromDateStr = dateFormatter.string(from: fromDay)
        let toDateStr = dateFormatter.string(from: today)
        
        var allPapers: [Paper] = []
        var totalRaw = 0
        
        for (trackName, trackConfig) in config.tracks {
            print("Fetching OpenAlex works for track [\(trackName)]...")
            do {
                let works = try await searchPapers(
                    query: trackConfig.query,
                    fromDate: fromDateStr,
                    toDate: toDateStr,
                    maxResults: resultsCap
                )
                totalRaw += works.count
                
                let parsed = works.map { parseWork($0, track: trackName) }
                let relevant = parsed.filter { isRelevant(paper: $0, trackName: trackName) }
                print("Track [\(trackName)]: found \(works.count) raw works, kept \(relevant.count) relevant")
                
                allPapers.append(contentsOf: relevant)
            } catch {
                print("Error searching papers for track \(trackName): \(error)")
            }
        }
        
        let merged = dedupeAndMergeTracks(papers: allPapers)
        return (merged, totalRaw, merged.count)
    }
}

