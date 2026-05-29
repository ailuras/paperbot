import Foundation

struct RecommendationResult {
    var paper: Paper
    var reason: String
    var slotIndex: Int
}

@MainActor
class RecommendEngine {
    let config: AppConfig
    
    init(config: AppConfig = ConfigManager.shared.config ?? AppConfig(
        openalex: OpenAlexConfig(base_url: "", mailto: "", api_key_env: "", timeout_seconds: 0, per_page: 0, default_days: 0, default_max_results: 0, topic_filter: ""),
        tracks: [:],
        scoring: ScoringConfig(tiers: [:], citation_breakpoints: [], max_citation_points: 0),
        recommendation: RecommendationConfig(daily_count: 3, quality_slots: 1, high_score_threshold: 5, recent_days: 30),
        translate: TranslateConfig(enabled: false, target_language: "中文", model: "", include_in_email: false, api_key_env: "", base_url: ""),
        mail: MailConfig(smtp_host: "", smtp_port: 0, smtp_user: "", smtp_password: "", from_addr: "", to_addrs: [], use_tls: false, dashboard_url: ""),
        semantic_scholar_key: ""
    )) {
        self.config = config
    }
    
    private func parsePubDate(paper: Paper) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: paper.publicationDate)
    }
    
    private func isRecent(paper: Paper, cutoff: Date) -> Bool {
        guard let pubDate = parsePubDate(paper: paper) else { return false }
        return pubDate >= cutoff
    }
    
    func recommend(papers: [Paper], count: Int? = nil) -> [RecommendationResult] {
        let recConfig = config.recommendation
        let dailyCount = count ?? recConfig.daily_count
        let qualitySlots = min(recConfig.quality_slots, dailyCount)
        let highThreshold = Double(recConfig.high_score_threshold)
        let recentDays = recConfig.recent_days
        
        if papers.isEmpty { return [] }
        
        let fileManager = FileManager.default
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -recentDays, to: Date()) else {
            return []
        }
        
        // Pools
        let pendingPapers = papers.filter { $0.status == "pending" }
        let recentPool = pendingPapers.filter { isRecent(paper: $0, cutoff: cutoffDate) }
        let highScorePool = pendingPapers.filter { $0.score >= highThreshold }
        
        var excludeIds = Set<String>()
        var selected: [RecommendationResult] = []
        
        func popRandom(from pool: [Paper]) -> Paper? {
            let valid = pool.filter { !excludeIds.contains($0.id) }
            guard let randomPaper = valid.randomElement() else { return nil }
            excludeIds.insert(randomPaper.id)
            return randomPaper
        }
        
        // 1. Quality priority slots
        for i in 0..<qualitySlots {
            var reason = "Quality Pick (score >= \(Int(highThreshold)))"
            var px = popRandom(from: highScorePool)
            
            if px == nil {
                px = popRandom(from: recentPool)
                reason = "Recent Pick (last \(recentDays)d)"
            }
            if px == nil {
                px = popRandom(from: pendingPapers)
                reason = "Exploration Pick"
            }
            
            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }
        
        // 2. Recency priority slots
        for i in qualitySlots..<dailyCount {
            var reason = "Recent Pick (last \(recentDays)d)"
            var px = popRandom(from: recentPool)
            
            if px == nil {
                px = popRandom(from: pendingPapers)
                reason = "Exploration Pick"
            }
            
            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }
        
        // Automatically mark recommended papers in Store
        for result in selected {
            PaperStore.shared.setPaperStatus(id: result.paper.id, status: "recommended")
        }
        
        return selected
    }
}
