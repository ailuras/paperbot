import Foundation
import Observation
import SwiftUI

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
    /// Research field abbreviation this venue belongs to (e.g. "SE", "AI",
    /// "FM", "PL", "AR", "DB"). A paper's field is its venue's field. Short
    /// codes keep manual venue entry consistent.
    var field: String?
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
@Observable
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Points awarded for each rating tier (1 = strongest). Used when building
    /// the scoring config from `venues`.
    static let tierPoints: [Int: Int] = [1: 10, 2: 7, 3: 5, 4: 2, 5: 1]

    // ── General ──────────────────────────────────────────────────────────
    /// Folder holding `vellumx.db`. Empty = default (see `defaultStorageDirectory`).
    var storageDirectory: String { didSet { save() } }
    var menuBarEnabled: Bool { didSet { save() } }
    /// UI language. "en" or "zh". Default English.
    var language: String { didSet { save() } }

    // ── API (DeepSeek translation) ───────────────────────────────────────
    var translateEnabled: Bool { didSet { save() } }
    var deepSeekBaseURL: String { didSet { save() } }
    var deepSeekModel: String { didSet { save() } }
    var targetLanguage: String { didSet { save() } }
    /// Bridges the Keychain-stored key into SwiftUI. Reads/writes the Keychain.
    var deepSeekAPIKey: String {
        didSet { Keychain.set(deepSeekAPIKey, for: Self.apiKeyAccount) }
    }

    // ── Recommendation knobs ─────────────────────────────────────────────
    var dailyCount: Int { didSet { save() } }
    var qualitySlots: Int { didSet { save() } }
    var highScoreThreshold: Int { didSet { save() } }
    var recentDays: Int { didSet { save() } }

    // ── OpenAlex fetch params ────────────────────────────────────────────
    var openAlexMailto: String { didSet { save() } }
    var perPage: Int { didSet { save() } }
    var defaultDays: Int { didSet { save() } }
    var defaultMaxResults: Int { didSet { save() } }
    var topicFilter: String { didSet { save() } }

    // ── Tracks / venues ──────────────────────────────────────────────────
    var tracks: [TrackPref] { didSet { save() } }
    var venues: [VenuePref] { didSet { save() } }

    // ── Sidebar label colors ─────────────────────────────────────────────
    /// Custom colors for sidebar filter labels, keyed "topic:<name>",
    /// "field:<name>", "tier:<n>" → a color name (see LabelColor). Absent =
    /// the category's default color.
    var labelColors: [String: String] { didSet { save() } }

    // ── Advanced ─────────────────────────────────────────────────────────
    /// Optional path to an external advanced config file. Empty = none.
    var advancedConfigPath: String { didSet { save() } }

    /// Bumped on every `save()` so `ConfigManager` can cache `effectiveConfig`.
    private(set) var configVersion: Int = 0

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
        func nonEmpty(_ value: String?, fallback: String) -> String {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return fallback
            }
            return value
        }

        storageDirectory   = stored?.storageDirectory ?? ""
        menuBarEnabled     = stored?.menuBarEnabled ?? true
        language           = stored?.language ?? "en"
        translateEnabled   = stored?.translateEnabled ?? d.translate.enabled
        deepSeekBaseURL    = nonEmpty(stored?.deepSeekBaseURL, fallback: d.translate.base_url)
        deepSeekModel      = nonEmpty(stored?.deepSeekModel, fallback: d.translate.model)
        targetLanguage     = nonEmpty(stored?.targetLanguage, fallback: d.translate.target_language)
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
        labelColors        = stored?.labelColors ?? [:]
        deepSeekAPIKey     = Keychain.get(Self.apiKeyAccount) ?? ""

        // Seed default tracks/venues. `seedVersion` lets us ship improved
        // defaults: when the bundled version is newer than what's stored, the
        // defaults are refreshed once. Below that, the user's edits are kept.
        if (stored?.seedVersion ?? 0) >= AppSettings.currentSeedVersion {
            let storedVenues = stored?.venues ?? []
            tracks = stored?.tracks ?? []
            venues = Self.normalizedVenues(storedVenues)
            if venues != storedVenues {
                save()
            }
        } else {
            tracks = AppSettings.defaultTracks
            venues = AppSettings.defaultVenues
            save()   // persist the new seed + version
        }
    }

    /// Bump when the bundled default tracks/venues change so existing installs
    /// refresh them once on next launch.
    static let currentSeedVersion = 7

    // MARK: - Derived taxonomy (for the sidebar filters)

    /// Distinct research fields across the venue table, in a stable order.
    var allFields: [String] {
        var seen = Set<String>(); var ordered: [String] = []
        for v in venues {
            guard let f = normalizedField(v.field), !seen.contains(f) else { continue }
            seen.insert(f); ordered.append(f)
        }
        if !seen.contains(Self.othersField) {
            ordered.append(Self.othersField)
        }
        return ordered.sorted()
    }

    /// Distinct tiers present in the venue table, ascending (1 = strongest).
    var allTiers: [Int] { Array(Set(venues.map(\.tier))).sorted() }

    /// The field a venue abbreviation belongs to (used to bucket a paper).
    func field(forAbbr abbr: String) -> String? {
        guard let venue = venues.first(where: { $0.abbr.caseInsensitiveCompare(abbr) == .orderedSame }) else {
            return Self.othersField
        }
        return normalizedField(venue.field) ?? Self.othersField
    }

    func color(forKey key: String, default defaultColor: LabelColor) -> Color {
        LabelColor.color(named: labelColors[key]) ?? defaultColor.color
    }

    func topicColor(_ topic: String) -> Color {
        color(forKey: "topic:\(topic)", default: .purple)
    }

    func fieldColor(_ field: String?) -> Color {
        if field == Self.othersField { return LabelColor.gray.color }
        guard let field, !field.isEmpty else { return LabelColor.orange.color }
        return color(forKey: "field:\(field)", default: .teal)
    }

    func tierColor(_ tier: Int) -> Color {
        let fallback: LabelColor
        switch tier {
        case 1: fallback = .red
        case 2: fallback = .orange
        case 3: fallback = .yellow
        default: fallback = .gray
        }
        return color(forKey: "tier:\(tier)", default: fallback)
    }

    /// Set or remove a custom label color. Must go through a copy-then-replace
    /// so the @Published dictionary fires objectWillChange.
    func setLabelColor(key: String, colorName: String?) {
        var colors = labelColors
        if let colorName {
            colors[key] = colorName
        } else {
            colors.removeValue(forKey: key)
        }
        labelColors = colors
    }

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
        // ── Tier 1 ──
        // Software engineering
        VenuePref(abbr: "ICSE",  phrase: "international conference on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "FSE",   phrase: "acm on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "ASE",   phrase: "automated software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "ISSTA", phrase: "software testing and analysis", tier: 1, field: "SE"),
        VenuePref(abbr: "TSE",   phrase: "transactions on software engineering", tier: 1, field: "SE"),
        VenuePref(abbr: "TOSEM", phrase: "software engineering and methodology", tier: 1, field: "SE"),
        // Programming languages (PACMPL covers POPL/PLDI/OOPSLA/ICFP)
        VenuePref(abbr: "PACMPL", phrase: "acm on programming languages", tier: 1, field: "PL"),
        VenuePref(abbr: "TOPLAS", phrase: "transactions on programming languages and systems", tier: 1, field: "PL"),
        // Formal methods / automated reasoning (top)
        VenuePref(abbr: "CAV",   phrase: "computer aided verification", tier: 1, field: "FM"),
        VenuePref(abbr: "CP",    phrase: "constraint programming", tier: 1, field: "AR"),
        VenuePref(abbr: "SAT",   phrase: "satisfiability testing", tier: 1, field: "AR"),
        VenuePref(abbr: "JAR",   phrase: "journal of automated reasoning", tier: 1, field: "AR"),
        // AI
        VenuePref(abbr: "AIJ",   phrase: "artificial intelligence", tier: 1, field: "AI", exact: true),
        VenuePref(abbr: "JAIR",  phrase: "journal of artificial intelligence research", tier: 1, field: "AI"),
        VenuePref(abbr: "AAAI",  phrase: "aaai conference on artificial intelligence", tier: 1, field: "AI"),
        VenuePref(abbr: "IJCAI", phrase: "international joint conference on artificial intelligence", tier: 1, field: "AI"),
        VenuePref(abbr: "NeurIPS", phrase: "neural information processing systems", tier: 1, field: "AI"),
        VenuePref(abbr: "ICLR",  phrase: "learning representations", tier: 1, field: "AI"),
        VenuePref(abbr: "ICML",  phrase: "international conference on machine learning", tier: 1, field: "AI"),

        // ── Tier 2 ──
        VenuePref(abbr: "TACAS", phrase: "tools and algorithms for the construction", tier: 2, field: "FM"),
        VenuePref(abbr: "CADE",  phrase: "automated deduction", tier: 2, field: "AR"),
        VenuePref(abbr: "IJCAR", phrase: "joint conference on automated reasoning", tier: 2, field: "AR"),
        VenuePref(abbr: "LICS",  phrase: "logic in computer science", tier: 2, field: "FM"),
        VenuePref(abbr: "FMCAD", phrase: "formal methods in computer-aided design", tier: 2, field: "FM"),
        VenuePref(abbr: "CONCUR", phrase: "concurrency theory", tier: 2, field: "FM"),
        VenuePref(abbr: "ESOP",  phrase: "european symposium on programming", tier: 2, field: "PL"),
        VenuePref(abbr: "ECOOP", phrase: "object-oriented programming", tier: 2, field: "PL"),
        VenuePref(abbr: "ICAPS", phrase: "automated planning and scheduling", tier: 2, field: "AI"),
        VenuePref(abbr: "FM",    phrase: "international symposium on formal methods", tier: 2, field: "FM"),
        VenuePref(abbr: "VMCAI", phrase: "verification, model checking", tier: 2, field: "FM"),
        VenuePref(abbr: "ITP",   phrase: "interactive theorem proving", tier: 2, field: "FM"),
        VenuePref(abbr: "EMSE",  phrase: "empirical software engineering", tier: 2, field: "SE"),
        VenuePref(abbr: "TOCL",  phrase: "transactions on computational logic", tier: 2, field: "FM"),
        VenuePref(abbr: "FMSD",  phrase: "formal methods in system design", tier: 2, field: "FM"),
        VenuePref(abbr: "STTT",  phrase: "software tools for technology transfer", tier: 2, field: "FM"),
        VenuePref(abbr: "FAoC",  phrase: "formal aspects of computing", tier: 2, field: "FM"),
        VenuePref(abbr: "SCP",   phrase: "science of computer programming", tier: 2, field: "PL"),

        // ── Tier 3 ──
        VenuePref(abbr: "ICST",  phrase: "software testing, verification and validation", tier: 3, field: "SE"),
        VenuePref(abbr: "SANER", phrase: "software analysis, evolution and reengineering", tier: 3, field: "SE"),
        VenuePref(abbr: "ICSME", phrase: "software maintenance and evolution", tier: 3, field: "SE"),
        VenuePref(abbr: "MSR",   phrase: "mining software repositories", tier: 3, field: "SE"),
        VenuePref(abbr: "SEFM",  phrase: "software engineering and formal methods", tier: 3, field: "FM"),
        VenuePref(abbr: "ICLP",  phrase: "logic programming", tier: 3, field: "AR"),
        VenuePref(abbr: "TABLEAUX", phrase: "analytic tableaux", tier: 3, field: "AR"),
        VenuePref(abbr: "SOCS",  phrase: "combinatorial search", tier: 3, field: "AI"),
        VenuePref(abbr: "EPTCS", phrase: "electronic proceedings in theoretical computer science", tier: 3, field: "FM"),

        // ── Tier 4: preprints ──
        VenuePref(abbr: "arXiv", phrase: "arxiv", tier: 4, field: "OT")
    ]

    private static let othersField = "Others"

    private func normalizedField(_ field: String?) -> String? {
        Self.normalizedField(field)
    }

    private static func normalizedField(_ field: String?) -> String? {
        guard let value = field?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value.caseInsensitiveCompare("Preprint") == .orderedSame ? "OT" : value
    }

    private static func normalizedVenues(_ venues: [VenuePref]) -> [VenuePref] {
        venues.map { venue in
            var normalized = venue
            normalized.field = normalizedField(venue.field)
            return normalized
        }
    }

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
        var labelColors: [String: String]?
        var seedVersion: Int?
    }

    private func save() {
        configVersion += 1
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
            labelColors: labelColors,
            seedVersion: AppSettings.currentSeedVersion
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
