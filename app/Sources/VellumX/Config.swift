import Foundation

struct TrackConfig {
    var query: String
    var keywords: [String]
    var color: String?
}

struct ScoringTier {
    var points: Int
}

// Persisted as JSON by MetadataStore, so this one keeps Codable.
struct CitationBreakpoint: Codable {
    var up_to: Int?
    var points_per_citation: Double
}

struct ScoringConfig {
    var tiers: [String: ScoringTier]
    var citation_breakpoints: [CitationBreakpoint]
    var max_citation_points: Int
}

struct RecommendationConfig {
    var daily_count: Int
    var quality_slots: Int
    var high_score_threshold: Int
    var recent_days: Int
}

struct TranslateConfig {
    var enabled: Bool
    var target_language: String
    var model: String
    var base_url: String
}

struct FiltersConfig {
    var title_blacklist: [String]?
    var source_blacklist: [String]?
    var venue_blacklist: [String]?
}

struct OpenAlexConfig {
    var base_url: String
    var mailto: String
    var per_page: Int
    var default_days: Int
    var default_max_results: Int
    var topic_filter: String
}

struct AppConfig {
    var openalex: OpenAlexConfig
    var tracks: [String: TrackConfig]
    var filters: FiltersConfig?
    var scoring: ScoringConfig
    var recommendation: RecommendationConfig
    var translate: TranslateConfig
}

/// Produces the effective `AppConfig` consumed by the engines. It is always
/// available (never nil): the taxonomy comes from `MetadataStore`,
/// personalization from `AppSettings`, and everything else from
/// `AppConfig.builtin`.
@MainActor
class ConfigManager {
    static let shared = ConfigManager()

    private var cached: AppConfig?
    private var cachedVersion: Int = -1

    private init() {}

    /// The merged config. Build order: built-in defaults → database taxonomy
    /// (venue tiers) → visual personalization (wins).
    var effectiveConfig: AppConfig {
        let version = AppSettings.shared.configVersion * 1_000_000 + MetadataStore.shared.metadataVersion
        if let cached, cachedVersion == version { return cached }
        let cfg = buildConfig()
        cached = cfg
        cachedVersion = version
        return cfg
    }

    private func buildConfig() -> AppConfig {
        var cfg = AppConfig.builtin
        let s = AppSettings.shared

        // Map each tier rank used by the venue rules to its point value.
        // Venue→tier matching itself is done by `VenueScorer` straight from
        // `MetadataStore.venues`; `scoring.tiers` only needs the points so
        // `calculateScore` can turn a tier into a base score.
        let metadata = MetadataStore.shared

        if !metadata.venues.isEmpty {
            var tiers: [String: ScoringTier] = [:]
            for tier in Set(metadata.venues.map(\.tier)) {
                let points = metadata.tiers.first(where: { $0.rank == tier })?.points
                    ?? MetadataStore.tierPoints[tier]
                    ?? max(1, 12 - 2 * tier)
                tiers[String(tier)] = ScoringTier(points: points)
            }
            cfg.scoring.tiers = tiers
        }

        // Citation scoring from the metadata store.
        cfg.scoring.citation_breakpoints = metadata.citationBreakpoints
        cfg.scoring.max_citation_points = metadata.maxCitationPoints

        // Personalization from the visual settings.
        cfg.recommendation = RecommendationConfig(
            daily_count: s.dailyCount,
            quality_slots: s.qualitySlots,
            high_score_threshold: s.highScoreThreshold,
            recent_days: s.recentDays
        )
        cfg.openalex.mailto = s.openAlexMailto
        cfg.openalex.per_page = s.perPage
        cfg.openalex.default_days = s.defaultDays
        cfg.openalex.default_max_results = s.defaultMaxResults
        cfg.openalex.topic_filter = s.topicFilter
        cfg.translate.enabled = s.translateEnabled
        if !s.deepSeekBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.base_url = s.deepSeekBaseURL
        }
        if !s.deepSeekModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.model = s.deepSeekModel
        }
        if !s.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cfg.translate.target_language = s.targetLanguage
        }
        if !metadata.topics.isEmpty {
            cfg.tracks = Dictionary(uniqueKeysWithValues: metadata.topics.map {
                ($0.name, TrackConfig(query: $0.query, keywords: $0.keywords, color: nil))
            })
        }
        return cfg
    }
}
