import Foundation

/// One academic track: an OpenAlex search query plus the keywords used to keep
/// only relevant results. Editable in Settings.
struct TrackPref: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var query: String
    var keywords: [String]
}

/// App-wide user settings, persisted as JSON under Application Support
/// (`~/Library/Application Support/VellumX/settings.json`). This is the "thin"
/// visual config: only personalization lives here. Rarely-changed values
/// (scoring, base URLs) come from `AppConfig.builtin`; advanced overrides can
/// come from an external config file (see `advancedConfigPath`).
///
/// The DeepSeek API key is sensitive and stored in the Keychain, not here.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // ── General ──────────────────────────────────────────────────────────
    /// Folder holding `vellumx.db`. Empty = default (`~/Documents/06-文献/VellumX`).
    @Published var storageDirectory: String { didSet { save() } }
    @Published var menuBarEnabled: Bool { didSet { save() } }

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

    // ── Tracks / keywords ────────────────────────────────────────────────
    @Published var tracks: [TrackPref] { didSet { save() } }

    // ── Advanced ─────────────────────────────────────────────────────────
    /// Optional path to an external advanced config file (scoring/filters
    /// overrides). Empty = none. Ghostty-style: set a path and open it.
    @Published var advancedConfigPath: String { didSet { save() } }

    private let url: URL
    private static let apiKeyAccount = "deepseek-api-key"

    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSettings.defaultStorageDirectory
    }

    static var defaultStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/06-文献/VellumX")
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
        tracks             = stored?.tracks ?? []
        advancedConfigPath = stored?.advancedConfigPath ?? ""
        deepSeekAPIKey     = Keychain.get(Self.apiKeyAccount) ?? ""
    }

    private struct Stored: Codable {
        var storageDirectory: String?
        var menuBarEnabled: Bool?
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
        var advancedConfigPath: String?
    }

    private func save() {
        let stored = Stored(
            storageDirectory: storageDirectory,
            menuBarEnabled: menuBarEnabled,
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
            advancedConfigPath: advancedConfigPath
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
