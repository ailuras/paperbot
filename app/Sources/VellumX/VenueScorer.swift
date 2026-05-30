import Foundation

@MainActor
class VenueScorer {
    let config: AppConfig?

    init(config: AppConfig? = ConfigManager.shared.effectiveConfig) {
        self.config = config
    }

    func getTier(venue: String) -> Int {
        guard let config = config else { return 0 }
        if venue.isEmpty { return 0 }
        let venueLower = venue.lowercased()

        // Blacklist check
        if let blacklist = config.filters?.venue_blacklist {
            for blocked in blacklist {
                if venueLower.contains(blocked.lowercased()) {
                    return 0
                }
            }
        }

        let tiers = config.scoring.tiers
        let sortedTierNums = tiers.keys.compactMap { Int($0) }.sorted()

        for tierNum in sortedTierNums {
            guard let tier = tiers[String(tierNum)] else { continue }
            guard let venues = tier.venues else { continue }

            for (abbr, phrases) in venues {
                // Word boundary check for abbreviation (e.g. \bcav\b)
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: abbr.lowercased()))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: venueLower, options: [], range: NSRange(location: 0, length: venueLower.utf16.count)) != nil {
                    return tierNum
                }

                // Phrase check
                for phrase in phrases {
                    let phraseLower = phrase.lowercased()
                    if venueLower.contains(phraseLower) {
                        if hasMoreSpecificLowerTierPhrase(venueLower: venueLower, phraseLower: phraseLower, currentTier: tierNum, sortedTiers: sortedTierNums) {
                            continue
                        }
                        return tierNum
                    }
                }
            }
        }

        return 0
    }

    private func hasMoreSpecificLowerTierPhrase(venueLower: String, phraseLower: String, currentTier: Int, sortedTiers: [Int]) -> Bool {
        guard let config = config else { return false }
        let lowerTiers = sortedTiers.filter { $0 > currentTier }

        for lowerTier in lowerTiers {
            guard let tier = config.scoring.tiers[String(lowerTier)], let venues = tier.venues else { continue }
            for phrases in venues.values {
                for lowerPhrase in phrases {
                    let lp = lowerPhrase.lowercased()
                    if lp.contains(phraseLower) && venueLower.contains(lp) && lp != phraseLower {
                        return true
                    }
                }
            }
        }
        return false
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
        if venueLower.contains("arxiv") {
            return "arXiv"
        }

        guard let config = config else { return "Others" }

        // Gather candidates (abbr, phrase)
        var candidates: [(abbr: String, phrase: String)] = []
        for tier in config.scoring.tiers.values {
            guard let venues = tier.venues else { continue }
            for (abbr, phrases) in venues {
                for phrase in phrases {
                    candidates.append((abbr, phrase))
                }
            }
        }

        // Sort by phrase length descending
        candidates.sort { $0.phrase.count > $1.phrase.count }

        for candidate in candidates {
            if venueLower.contains(candidate.phrase.lowercased()) {
                return candidate.abbr
            }
        }

        // Fallback to checking exact word boundary for acronym
        for tier in config.scoring.tiers.values {
            guard let venues = tier.venues else { continue }
            for abbr in venues.keys {
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: abbr.lowercased()))\\b"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: venueLower, options: [], range: NSRange(location: 0, length: venueLower.utf16.count)) != nil {
                    return abbr
                }
            }
        }

        return "Others"
    }
}
