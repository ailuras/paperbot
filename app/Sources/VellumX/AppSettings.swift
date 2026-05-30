import Foundation

/// One academic track: an OpenAlex search query plus the keywords used to keep
/// only relevant results. Editable in Settings.
struct TrackPref: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var query: String
    var keywords: [String]
}

/// One venue rating used for scoring. `phrase` is matched (case-insensitive)
/// against the paper's venue; `abbr` is the short label; `tier` is the rating
/// (1 = strongest). Editable in Settings.
struct VenuePref: Codable, Identifiable, Equatable {
    var id = UUID()
    var abbr: String
    var phrase: String
    var tier: Int
    /// When true, `phrase` must equal the whole venue name (case-insensitive),
    /// not just be a substring. Used for short journal names like "Artificial
    /// Intelligence" that would otherwise over-match (AAAI, FLAIRS, …).
    var exact: Bool?
}

/// App-wide user settings, persisted as JSON under Application Support
/// (`~/Library/Application Support/VellumX/settings.json`). This is the "thin"
/// visual config: only personalization lives here. Rarely-changed values
/// (citation curve, base URLs) come from `AppConfig.builtin`; advanced
/// overrides can come from an external config file (see `advancedConfigPath`).
///
/// The DeepSeek API key is sensitive and stored in the Keychain, not here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Points awarded for each rating tier (1 = strongest). Used when building
    /// the scoring config from `venues`.
    static let tierPoints: [Int: Int] = [1: 10, 2: 7, 3: 5, 4: 2, 5: 1]

    // ── General ──────────────────────────────────────────────────────────
    /// Folder holding `vellumx.db`. Empty = default (see `defaultStorageDirectory`).
    @Published var storageDirectory: String { didSet { save() } }
    @Published var menuBarEnabled: Bool { didSet { save() } }
    /// UI language. "en" or "zh". Default English.
    @Published var language: String { didSet { save() } }

    // ── API (DeepSeek translation) ───────────────────────────────────────
    @Published var translateEnabled: Bool { didSet { save() } }
    @Published var deepSeekBaseURL: String { didSet { save() } }
    @Published var deepSeekModel: String { didSet { save() } }
    @Published var targetLanguage: String { didSet { save() } }
    /// Bridges the Keychain-stored key into SwiftUI. Reads/writes the Keychain.
    @Published var deepSeekAPIKey: String {
        didSet { Keychain.set(deepSeekAPIKey, for: Self.apiKeyAccount) }
    }

    // ── Recommendation knobs ─────────────────────────────────────────────
    @Published var dailyCount: Int { didSet { save() } }
    @Published var qualitySlots: Int { didSet { save() } }
    @Published var highScoreThreshold: Int { didSet { save() } }
    @Published var recentDays: Int { didSet { save() } }

    // ── OpenAlex fetch params ────────────────────────────────────────────
    @Published var openAlexMailto: String { didSet { save() } }
    @Published var perPage: Int { didSet { save() } }
    @Published var defaultDays: Int { didSet { save() } }
    @Published var defaultMaxResults: Int { didSet { save() } }
    @Published var topicFilter: String { didSet { save() } }

    // ── Tracks / venues ──────────────────────────────────────────────────
    @Published var tracks: [TrackPref] { didSet { save() } }
    @Published var venues: [VenuePref] { didSet { save() } }

    // ── Advanced ─────────────────────────────────────────────────────────
    /// Optional path to an external advanced config file. Empty = none.
    @Published var advancedConfigPath: String { didSet { save() } }

    private let url: URL
    private static let apiKeyAccount = "deepseek-api-key"

    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSettings.defaultStorageDirectory
    }

    /// Distribution-friendly default: a visible, iCloud-syncable folder in the
    /// user's Documents that doesn't assume any personal directory layout.
    static var defaultStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VellumX")
    }

    init(filename: String = "settings.json") {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VellumX")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent(filename)

        let stored = (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(Stored.self, from: $0)
        }
        let d = AppConfig.builtin   // pull defaults from the built-in config

        storageDirectory   = stored?.storageDirectory ?? ""
        menuBarEnabled     = stored?.menuBarEnabled ?? true
        language           = stored?.language ?? "en"
        translateEnabled   = stored?.translateEnabled ?? d.translate.enabled
        deepSeekBaseURL    = stored?.deepSeekBaseURL ?? d.translate.base_url
        deepSeekModel      = stored?.deepSeekModel ?? d.translate.model
        targetLanguage     = stored?.targetLanguage ?? d.translate.target_language
        dailyCount         = stored?.dailyCount ?? d.recommendation.daily_count
        qualitySlots       = stored?.qualitySlots ?? d.recommendation.quality_slots
        highScoreThreshold = stored?.highScoreThreshold ?? d.recommendation.high_score_threshold
        recentDays         = stored?.recentDays ?? d.recommendation.recent_days
        openAlexMailto     = stored?.openAlexMailto ?? d.openalex.mailto
        perPage            = stored?.perPage ?? d.openalex.per_page
        defaultDays        = stored?.defaultDays ?? d.openalex.default_days
        defaultMaxResults  = stored?.defaultMaxResults ?? d.openalex.default_max_results
        topicFilter        = stored?.topicFilter ?? d.openalex.topic_filter
        advancedConfigPath = stored?.advancedConfigPath ?? ""
        deepSeekAPIKey     = Keychain.get(Self.apiKeyAccount) ?? ""

        // Seed default tracks/venues. `seedVersion` lets us ship improved
        // defaults: when the bundled version is newer than what's stored, the
        // defaults are refreshed once. Below that, the user's edits are kept.
        if (stored?.seedVersion ?? 0) >= AppSettings.currentSeedVersion {
            tracks = stored?.tracks ?? []
            venues = stored?.venues ?? []
        } else {
            tracks = AppSettings.defaultTracks
            venues = AppSettings.defaultVenues
            save()   // persist the new seed + version
        }
    }

    /// Bump when the bundled default tracks/venues change so existing installs
    /// refresh them once on next launch.
    static let currentSeedVersion = 5

    // MARK: - Defaults (SAT / SMT / CP focus)

    /// Interests are the three solving paradigms (SAT / SMT / CP). Their papers
    /// can come from any field — AI, software engineering, formal methods — so
    /// the queries/keywords target the technique, while the venue ratings (which
    /// span all those fields) handle scoring.
    static let defaultTracks: [TrackPref] = [
        TrackPref(name: "SAT", query: "SAT solver boolean satisfiability",
                  keywords: ["sat solver", "boolean satisfiability", "propositional satisfiability",
                             "cdcl", "conflict-driven clause learning", "maxsat", "sat solving"]),
        TrackPref(name: "SMT", query: "satisfiability modulo theories SMT solver",
                  keywords: ["smt solver", "satisfiability modulo theories", "smt",
                             "z3", "cvc5", "theory solver", "bit-vector"]),
        TrackPref(name: "CP", query: "constraint programming constraint satisfaction",
                  keywords: ["constraint programming", "constraint satisfaction", "constraint solver",
                             "constraint propagation", "global constraint", "csp"])
    ]

    /// Default venue ratings for a software-engineering + automated-reasoning
    /// researcher. Tier 1 = strongest. `phrase` is matched case-insensitively
    /// against the OpenAlex venue display name, so phrases are chosen to be
    /// substrings of how OpenAlex actually labels each venue. The user can edit
    /// all of this in Settings ▸ Papers.
    static let defaultVenues: [VenuePref] = [
        // ── Tier 1: top software engineering + automated reasoning + AI/PL ──
        // Software engineering
        VenuePref(abbr: "ICSE",  phrase: "international conference on software engineering", tier: 1),
        VenuePref(abbr: "FSE",   phrase: "acm on software engineering", tier: 1),
        VenuePref(abbr: "ASE",   phrase: "automated software engineering", tier: 1),
        VenuePref(abbr: "ISSTA", phrase: "software testing and analysis", tier: 1),
        VenuePref(abbr: "TSE",   phrase: "transactions on software engineering", tier: 1),
        VenuePref(abbr: "TOSEM", phrase: "software engineering and methodology", tier: 1),
        // Programming languages (PACMPL covers POPL/PLDI/OOPSLA/ICFP)
        VenuePref(abbr: "PACMPL", phrase: "acm on programming languages", tier: 1),
        VenuePref(abbr: "TOPLAS", phrase: "transactions on programming languages and systems", tier: 1),
        // Automated reasoning / constraint solving (top)
        VenuePref(abbr: "CAV",   phrase: "computer aided verification", tier: 1),
        VenuePref(abbr: "CP",    phrase: "constraint programming", tier: 1),
        VenuePref(abbr: "SAT",   phrase: "satisfiability testing", tier: 1),
        VenuePref(abbr: "JAR",   phrase: "journal of automated reasoning", tier: 1),
        VenuePref(abbr: "AIJ",   phrase: "artificial intelligence", tier: 1, exact: true),
        VenuePref(abbr: "JAIR",  phrase: "journal of artificial intelligence research", tier: 1),
        VenuePref(abbr: "AAAI",  phrase: "aaai conference on artificial intelligence", tier: 1),
        VenuePref(abbr: "IJCAI", phrase: "international joint conference on artificial intelligence", tier: 1),

        // ── Tier 2: strong FM / verification / SE / DB venues ──
        VenuePref(abbr: "TACAS", phrase: "tools and algorithms for the construction", tier: 2),
        VenuePref(abbr: "CADE",  phrase: "automated deduction", tier: 2),
        VenuePref(abbr: "IJCAR", phrase: "joint conference on automated reasoning", tier: 2),
        VenuePref(abbr: "LICS",  phrase: "logic in computer science", tier: 2),
        VenuePref(abbr: "FMCAD", phrase: "formal methods in computer-aided design", tier: 2),
        VenuePref(abbr: "CONCUR", phrase: "concurrency theory", tier: 2),
        VenuePref(abbr: "ESOP",  phrase: "european symposium on programming", tier: 2),
        VenuePref(abbr: "ECOOP", phrase: "object-oriented programming", tier: 2),
        VenuePref(abbr: "ICAPS", phrase: "automated planning and scheduling", tier: 2),
        VenuePref(abbr: "FM",    phrase: "international symposium on formal methods", tier: 2),
        VenuePref(abbr: "VMCAI", phrase: "verification, model checking", tier: 2),
        VenuePref(abbr: "ITP",   phrase: "interactive theorem proving", tier: 2),
        VenuePref(abbr: "EMSE",  phrase: "empirical software engineering", tier: 2),
        VenuePref(abbr: "TOCL",  phrase: "transactions on computational logic", tier: 2),
        VenuePref(abbr: "FMSD",  phrase: "formal methods in system design", tier: 2),
        VenuePref(abbr: "STTT",  phrase: "software tools for technology transfer", tier: 2),
        VenuePref(abbr: "FAoC",  phrase: "formal aspects of computing", tier: 2),
        VenuePref(abbr: "SCP",   phrase: "science of computer programming", tier: 2),
        VenuePref(abbr: "VLDB",  phrase: "vldb endowment", tier: 2),
        VenuePref(abbr: "SIGMOD", phrase: "acm on management of data", tier: 2),

        // ── Tier 3: solid specialized venues ──
        VenuePref(abbr: "ICST",  phrase: "software testing, verification and validation", tier: 3),
        VenuePref(abbr: "SANER", phrase: "software analysis, evolution and reengineering", tier: 3),
        VenuePref(abbr: "ICSME", phrase: "software maintenance and evolution", tier: 3),
        VenuePref(abbr: "MSR",   phrase: "mining software repositories", tier: 3),
        VenuePref(abbr: "SEFM",  phrase: "software engineering and formal methods", tier: 3),
        VenuePref(abbr: "ICLP",  phrase: "logic programming", tier: 3),
        VenuePref(abbr: "TABLEAUX", phrase: "analytic tableaux", tier: 3),
        VenuePref(abbr: "SOCS",  phrase: "combinatorial search", tier: 3),
        VenuePref(abbr: "EPTCS", phrase: "electronic proceedings in theoretical computer science", tier: 3),

        // ── Tier 4: preprints ──
        VenuePref(abbr: "arXiv", phrase: "arxiv", tier: 4)
    ]

    private struct Stored: Codable {
        var storageDirectory: String?
        var menuBarEnabled: Bool?
        var language: String?
        var translateEnabled: Bool?
        var deepSeekBaseURL: String?
        var deepSeekModel: String?
        var targetLanguage: String?
        var dailyCount: Int?
        var qualitySlots: Int?
        var highScoreThreshold: Int?
        var recentDays: Int?
        var openAlexMailto: String?
        var perPage: Int?
        var defaultDays: Int?
        var defaultMaxResults: Int?
        var topicFilter: String?
        var tracks: [TrackPref]?
        var venues: [VenuePref]?
        var advancedConfigPath: String?
        var seedVersion: Int?
    }

    private func save() {
        let stored = Stored(
            storageDirectory: storageDirectory,
            menuBarEnabled: menuBarEnabled,
            language: language,
            translateEnabled: translateEnabled,
            deepSeekBaseURL: deepSeekBaseURL,
            deepSeekModel: deepSeekModel,
            targetLanguage: targetLanguage,
            dailyCount: dailyCount,
            qualitySlots: qualitySlots,
            highScoreThreshold: highScoreThreshold,
            recentDays: recentDays,
            openAlexMailto: openAlexMailto,
            perPage: perPage,
            defaultDays: defaultDays,
            defaultMaxResults: defaultMaxResults,
            topicFilter: topicFilter,
            tracks: tracks,
            venues: venues,
            advancedConfigPath: advancedConfigPath,
            seedVersion: AppSettings.currentSeedVersion
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
