import Foundation

class VenueScorer {
    let config: AppConfig?
    
    // Pre-built caches for O(1) exact-match and O(k) substring-match lookups.
    private let exactMatches: [String: (tier: Int, abbr: String)]
    private let substringMatches: [(phrase: String, tier: Int, abbr: String)]
    
    init(config: AppConfig?, venues: [VenuePref] = []) {
        self.config = config
        
        var exact: [String: (tier: Int, abbr: String)] = [:]
        var substring: [(phrase: String, tier: Int, abbr: String)] = []
        
        for v in venues where !v.phrase.isEmpty {
            let key = v.phrase.lowercased()
            if v.exact == true {
                // For exact matches, keep the strongest tier (lowest number).
                if let existing = exact[key] {
                    if v.tier < existing.tier {
                        exact[key] = (v.tier, v.abbr)
                    }
                } else {
                    exact[key] = (v.tier, v.abbr)
                }
            } else {
                substring.append((key, v.tier, v.abbr))
            }
        }
        
        // Longer phrases first = more specific matches take priority.
        substring.sort { $0.phrase.count > $1.phrase.count }
        
        self.exactMatches = exact
        self.substringMatches = substring
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

        // 1. Exact-match cache (O(1))
        if let match = exactMatches[venueLower] {
            return match.tier
        }
        
        // 2. Substring-match cache (O(k), k = number of substring rules)
        var best: (tier: Int, len: Int)?
        for rule in substringMatches {
            if venueLower.contains(rule.phrase) {
                let len = rule.phrase.count
                if best == nil || rule.tier < best!.tier || (rule.tier == best!.tier && len > best!.len) {
                    best = (rule.tier, len)
                }
            }
        }
        if let best { return best.tier }

        // Fallback: advanced-config scoring tiers (when no visual venues set).
        guard let config = config else { return 0 }
        let tiers = config.scoring.tiers
        let sortedTierNums = tiers.keys.compactMap { Int($0) }.sorted()
        for tierNum in sortedTierNums {
            guard let tierVenues = tiers[String(tierNum)]?.venues else { continue }
            for (_, phrases) in tierVenues {
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

        // 1. Exact-match cache (O(1))
        if let match = exactMatches[venueLower] {
            return match.abbr
        }
        
        // 2. Substring-match cache (O(k))
        for rule in substringMatches {
            if venueLower.contains(rule.phrase) {
                return rule.abbr
            }
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
