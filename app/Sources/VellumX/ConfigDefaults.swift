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
            data_dir: nil,
            openalex: OpenAlexConfig(
                base_url: "https://api.openalex.org/works",
                mailto: "",
                api_key_env: "OPENALEX_API_KEY",
                timeout_seconds: 20,
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
                include_in_email: false,
                api_key_env: "DEEPSEEK_API_KEY",
                base_url: "https://api.deepseek.com"
            ),
            mail: MailConfig(
                smtp_host: "", smtp_port: 0, smtp_user: "", smtp_password: "",
                from_addr: "", to_addrs: [], use_tls: false, dashboard_url: ""
            ),
            semantic_scholar_key: nil
        )
    }

    /// A small default set of high-profile venues so freshly fetched papers get
    /// a non-zero tier out of the box. Users who want the full PaperBot venue
    /// list can supply an advanced config file. Keys are tier numbers (lower =
    /// stronger); `points` is the base score for that tier.
    private static var builtinTiers: [String: ScoringTier] {
        [
            "1": ScoringTier(points: 10, venues: [
                "Nature": ["nature"],
                "Science": ["science"],
                "CVPR": ["computer vision and pattern recognition"],
                "ICCV": ["international conference on computer vision"],
                "NeurIPS": ["neural information processing systems"],
                "ICML": ["international conference on machine learning"],
                "ICLR": ["international conference on learning representations"]
            ]),
            "2": ScoringTier(points: 6, venues: [
                "ECCV": ["european conference on computer vision"],
                "AAAI": ["aaai conference on artificial intelligence"],
                "ACL": ["annual meeting of the association for computational linguistics"],
                "EMNLP": ["empirical methods in natural language processing"],
                "SIGGRAPH": ["siggraph"]
            ]),
            "3": ScoringTier(points: 3, venues: [
                "arXiv": ["arxiv"]
            ])
        ]
    }
}
