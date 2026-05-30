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

        // Seed default tracks/venues once, so the app is useful out of the box
        // (and the user can edit them). A flag avoids re-seeding after the user
        // intentionally clears them.
        if stored?.didSeedDefaults == true {
            tracks = stored?.tracks ?? []
            venues = stored?.venues ?? []
        } else {
            tracks = (stored?.tracks?.isEmpty == false) ? stored!.tracks! : AppSettings.defaultTracks
            venues = (stored?.venues?.isEmpty == false) ? stored!.venues! : AppSettings.defaultVenues
            save()   // persist the seed + flag
        }
    }

    // MARK: - Defaults (SAT / SMT / CP focus)

    static let defaultTracks: [TrackPref] = [
        TrackPref(name: "SAT", query: "SAT solver satisfiability",
                  keywords: ["sat solver", "satisfiability", "cdcl", "boolean satisfiability"]),
        TrackPref(name: "SMT", query: "satisfiability modulo theories",
                  keywords: ["smt", "satisfiability modulo theories", "smt solver", "z3", "cvc5"]),
        TrackPref(name: "CP", query: "constraint programming",
                  keywords: ["constraint programming", "constraint satisfaction", "csp", "constraint solver"])
    ]

    static let defaultVenues: [VenuePref] = [
        VenuePref(abbr: "CAV",   phrase: "computer aided verification", tier: 1),
        VenuePref(abbr: "POPL",  phrase: "principles of programming languages", tier: 1),
        VenuePref(abbr: "PLDI",  phrase: "programming language design and implementation", tier: 1),
        VenuePref(abbr: "LICS",  phrase: "logic in computer science", tier: 1),
        VenuePref(abbr: "TACAS", phrase: "tools and algorithms for the construction", tier: 2),
        VenuePref(abbr: "CADE",  phrase: "automated deduction", tier: 2),
        VenuePref(abbr: "IJCAR", phrase: "joint conference on automated reasoning", tier: 2),
        VenuePref(abbr: "FMCAD", phrase: "formal methods in computer-aided design", tier: 2),
        VenuePref(abbr: "SAT",   phrase: "theory and applications of satisfiability testing", tier: 3),
        VenuePref(abbr: "CP",    phrase: "principles and practice of constraint programming", tier: 3),
        VenuePref(abbr: "CPAIOR", phrase: "integration of constraint programming", tier: 3),
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
        var didSeedDefaults: Bool?
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
            didSeedDefaults: true
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
