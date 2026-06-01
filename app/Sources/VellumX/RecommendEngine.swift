import Foundation

struct RecommendationResult {
    var paper: Paper
    var reason: String
    var slotIndex: Int
}

class RecommendEngine {
    let config: AppConfig

    init(config: AppConfig) {
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

    func recommend(papers: [Paper], count: Int? = nil) -> (selected: [RecommendationResult], resetIds: [String]) {
        let recConfig = config.recommendation
        let dailyCount = count ?? recConfig.daily_count
        let qualitySlots = min(recConfig.quality_slots, dailyCount)
        let highThreshold = Double(recConfig.high_score_threshold)
        let recentDays = recConfig.recent_days

        if papers.isEmpty { return (selected: [], resetIds: []) }

        // Collect active recommendations to reset so repeated runs replace the
        // day's picks without changing the user's lifecycle status.
        let toReset = papers.filter(\.isRecommended).map(\.id)

        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -recentDays, to: Date()) else {
            return (selected: [], resetIds: [])
        }

        // Pools. Prior recommendations are treated as candidates because
        // callers apply `resetIds` after selection.
        let candidatePapers = papers.filter { $0.status == .pending || $0.isRecommended }
        let recentPool = candidatePapers.filter { isRecent(paper: $0, cutoff: cutoffDate) }
        let highScorePool = candidatePapers.filter { $0.score >= highThreshold }

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
                px = popRandom(from: candidatePapers)
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
                px = popRandom(from: candidatePapers)
                reason = "Exploration Pick"
            }

            if let chosen = px {
                selected.append(RecommendationResult(paper: chosen, reason: reason, slotIndex: i))
            }
        }

        return (selected: selected, resetIds: toReset)
    }
}
