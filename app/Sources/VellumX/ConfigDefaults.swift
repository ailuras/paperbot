import Foundation

/// Built-in defaults for the parts of `AppConfig` that rarely change and are
/// therefore baked into the app rather than surfaced in the visual settings:
/// API base URLs, timeouts, the citation-score curve, and a modest set of
/// well-known venue tiers. The advanced config file (see `ConfigManager`) can
/// override `scoring`/`filters`; the visual settings (`AppSettings`) override
/// the personalization fields (tracks, recommendation knobs, OpenAlex params,
/// translation).
extension AppConfig {
    static var builtin: AppConfig {
        AppConfig(
            openalex: OpenAlexConfig(
                base_url: "https://api.openalex.org/works",
                mailto: "",
                per_page: 100,
                default_days: 45,
                default_max_results: 1000,
                topic_filter: "topics.field.id:17"   // 17 = Computer Science
            ),
            tracks: [:],
            filters: FiltersConfig(
                title_blacklist: [],
                source_blacklist: [],
                venue_blacklist: []
            ),
            scoring: ScoringConfig(
                tiers: builtinTiers,
                citation_breakpoints: [
                    CitationBreakpoint(up_to: 10, points_per_citation: 0.5),
                    CitationBreakpoint(up_to: 50, points_per_citation: 0.2),
                    CitationBreakpoint(up_to: nil, points_per_citation: 0.05)
                ],
                max_citation_points: 40
            ),
            recommendation: RecommendationConfig(
                daily_count: 3,
                quality_slots: 1,
                high_score_threshold: 5,
                recent_days: 30
            ),
            translate: TranslateConfig(
                enabled: true,
                target_language: "中文",
                model: "deepseek-chat",
                base_url: "https://api.deepseek.com"
            )
        )
    }

    /// Venue tiers are intentionally empty by default. Paper abbreviations and
    /// tiers come solely from the user-editable venue rules (see
    /// `MetadataStore`), which are pre-seeded on first launch — so there is a
    /// single, visible source of truth. Advanced users can still supply a
    /// config file with explicit `scoring.tiers`, which `VenueScorer` honors as
    /// a fallback; we just no longer inject hidden built-in defaults.
    private static var builtinTiers: [String: ScoringTier] { [:] }
}
