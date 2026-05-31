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
    var color: String? = nil
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
/// (`~/Library/Application Support/VellumX/settings.json`). This is the thin
/// config file: only global preferences and tuning knobs live here. The paper
/// taxonomy (tracks, venues, fields, tiers, label colors) is owned by
/// `MetadataStore` in the database; rarely-changed values (citation curve, base
/// URLs) come from `AppConfig.builtin`.
///
/// The DeepSeek API key is sensitive and stored in the Keychain, not here.
@MainActor
@Observable
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

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

    /// Bumped on every `save()` so `ConfigManager` can cache `effectiveConfig`.
    private(set) var configVersion: Int = 0

    private let url: URL
    private static let apiKeyAccount = "deepseek-api-key"

    /// On-disk location of settings.json (the editable developer config).
    var settingsFileURL: URL { url }

    var resolvedStorageDirectory: URL {
        if !storageDirectory.isEmpty {
            return URL(fileURLWithPath: (storageDirectory as NSString).expandingTildeInPath)
        }
        return AppSettings.defaultStorageDirectory
    }

    /// Default home for the database: the conventional macOS application-data
    /// location. Kept local (not iCloud Drive) on purpose — the WAL-mode SQLite
    /// store has `-wal`/`-shm` sidecar files that iCloud would sync out of step
    /// with the main file and corrupt. Users can still point elsewhere.
    static var defaultStorageDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VellumX")
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
        deepSeekAPIKey     = Keychain.get(Self.apiKeyAccount) ?? ""

        // settings.json is the editable developer config: materialize it with
        // defaults the first time so every knob is visible and hand-editable.
        if !FileManager.default.fileExists(atPath: url.path) {
            save()
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
            topicFilter: topicFilter
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(stored).write(to: url, options: .atomic)
    }
}
