import Foundation

struct TrackConfig: Codable {
    var query: String
    var keywords: [String]
    var color: String?
}

struct ScoringTier: Codable {
    var points: Int
    var venues: [String: [String]]?
}

struct CitationBreakpoint: Codable {
    var up_to: Int?
    var points_per_citation: Double
}

struct ScoringConfig: Codable {
    var tiers: [String: ScoringTier]
    var citation_breakpoints: [CitationBreakpoint]
    var max_citation_points: Int
}

struct RecommendationConfig: Codable {
    var daily_count: Int
    var quality_slots: Int
    var high_score_threshold: Int
    var recent_days: Int
}

struct TranslateConfig: Codable {
    var enabled: Bool
    var target_language: String
    var model: String
    var include_in_email: Bool
    var api_key_env: String
    var base_url: String
}

struct MailConfig: Codable {
    var smtp_host: String
    var smtp_port: Int
    var smtp_user: String
    var smtp_password: String
    var from_addr: String
    var to_addrs: [String]
    var use_tls: Bool
    var dashboard_url: String
}

struct FiltersConfig: Codable {
    var title_blacklist: [String]?
    var source_blacklist: [String]?
    var venue_blacklist: [String]?
}

struct OpenAlexConfig: Codable {
    var base_url: String
    var mailto: String
    var api_key_env: String
    var timeout_seconds: Int
    var per_page: Int
    var default_days: Int
    var default_max_results: Int
    var topic_filter: String
}

struct AppConfig: Codable {
    var data_dir: String?
    var openalex: OpenAlexConfig
    var tracks: [String: TrackConfig]
    var filters: FiltersConfig?
    var scoring: ScoringConfig
    var recommendation: RecommendationConfig
    var translate: TranslateConfig
    var mail: MailConfig
}

@MainActor
class ConfigManager {
    static let shared = ConfigManager()
    var config: AppConfig?

    private init() {
        loadConfig()
    }

    func loadConfig() {
        let fileManager = FileManager.default
        var configPath: URL?

        // 1. Check environment variable
        if let envPath = ProcessInfo.processInfo.environment["PAPERBOT_CONFIG"] {
            configPath = URL(fileURLWithPath: envPath)
        }

        // 2. Check ~/.paperbot/config.json
        if configPath == nil {
            let home = fileManager.homeDirectoryForCurrentUser
            let dotPath = home.appendingPathComponent(".paperbot/config.json")
            if fileManager.fileExists(atPath: dotPath.path) {
                configPath = dotPath
            }
        }

        // 3. Fallback to workspace data/config.json or relative data/config.json
        if configPath == nil {
            let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            let workspacePath = currentDir.appendingPathComponent("data/config.json")
            if fileManager.fileExists(atPath: workspacePath.path) {
                configPath = workspacePath
            }
        }

        guard let path = configPath else {
            print("Warning: config.json not found in env, ~/.paperbot, or current dir")
            return
        }

        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            self.config = try decoder.decode(AppConfig.self, from: data)
            print("Successfully loaded config from \(path.path)")
        } catch {
            print("Error loading config from \(path.path): \(error)")
        }
    }
}
