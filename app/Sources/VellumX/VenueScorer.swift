import Foundation

@MainActor
class VenueScorer {
    let config: AppConfig?

    init(config: AppConfig? = ConfigManager.shared.effectiveConfig) {
        self.config = config
    }

    func getTier(venue: String) -> Int {
        if venue.isEmpty { return 0 }
        let venueLower = venue.lowercased()

        // Blacklist check
        if let blacklist = config?.filters?.venue_blacklist {
            for blocked in blacklist where venueLower.contains(blocked.lowercased()) {
                return 0
            }
        }

        // Prefer the editable venue ratings (the source of truth). Strongest
        // tier (lowest number) wins; on a tie, the longer phrase wins (more
        // specific). Exact-flagged entries must match the whole venue name.
        let prefs = AppSettings.shared.venues
        if !prefs.isEmpty {
            var best: (tier: Int, len: Int)?
            for p in prefs where !p.phrase.isEmpty {
                let phrase = p.phrase.lowercased()
                let matched = (p.exact == true) ? (venueLower == phrase) : venueLower.contains(phrase)
                guard matched else { continue }
                if best == nil || p.tier < best!.tier || (p.tier == best!.tier && phrase.count > best!.len) {
                    best = (p.tier, phrase.count)
                }
            }
            return best?.tier ?? 0
        }

        // Fallback: advanced-config scoring tiers (when no visual venues set).
        guard let config = config else { return 0 }
        let tiers = config.scoring.tiers
        let sortedTierNums = tiers.keys.compactMap { Int($0) }.sorted()
        for tierNum in sortedTierNums {
            guard let venues = tiers[String(tierNum)]?.venues else { continue }
            for (_, phrases) in venues {
                for phrase in phrases where venueLower.contains(phrase.lowercased()) {
                    return tierNum
                }
            }
        }
        return 0
    }

    func citationScore(citations: Int) -> Double {
        guard let config = config else { return 0.0 }
        var remaining = Double(citations)
        var previousLimit = 0.0
        var score = 0.0

        for seg in config.scoring.citation_breakpoints {
            let rate = seg.points_per_citation
            if let upTo = seg.up_to {
                let limit = Double(upTo)
                let count = max(0.0, min(remaining, limit - previousLimit))
                score += count * rate
                remaining -= count
                previousLimit = limit
            } else {
                let count = max(0.0, remaining)
                score += count * rate
                remaining -= count
            }
            if remaining <= 0 {
                break
            }
        }

        return min(score, Double(config.scoring.max_citation_points))
    }

    func calculateScore(venue: String, citations: Int) -> Double {
        let tier = getTier(venue: venue)
        var base = 0.0
        if let config = config, let tierConfig = config.scoring.tiers[String(tier)] {
            base = Double(tierConfig.points)
        }
        return base + citationScore(citations: citations)
    }

    func computeVenueAbbr(venue: String) -> String {
        if venue.isEmpty { return "Others" }
        let venueLower = venue.lowercased()
        if venueLower.contains("arxiv") { return "arXiv" }

        // Use the editable venue ratings: the longest matching phrase wins
        // (most specific), with exact entries requiring a full-name match.
        let prefs = AppSettings.shared.venues
        if !prefs.isEmpty {
            var best: (abbr: String, len: Int)?
            for p in prefs where !p.phrase.isEmpty {
                let phrase = p.phrase.lowercased()
                let matched = (p.exact == true) ? (venueLower == phrase) : venueLower.contains(phrase)
                if matched, best == nil || phrase.count > best!.len {
                    best = (p.abbr, phrase.count)
                }
            }
            if let best { return best.abbr }
            return "Others"
        }

        // Fallback: advanced-config scoring tiers.
        guard let config = config else { return "Others" }
        var candidates: [(abbr: String, phrase: String)] = []
        for tier in config.scoring.tiers.values {
            guard let venues = tier.venues else { continue }
            for (abbr, phrases) in venues {
                for phrase in phrases { candidates.append((abbr, phrase)) }
            }
        }
        candidates.sort { $0.phrase.count > $1.phrase.count }
        for candidate in candidates where venueLower.contains(candidate.phrase.lowercased()) {
            return candidate.abbr
        }
        return "Others"
    }
}
