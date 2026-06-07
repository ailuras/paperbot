import Foundation
import Observation

@MainActor
@Observable
final class AutomationPreferences {
    static let shared = AutomationPreferences()

    var automationEnabled: Bool { didSet { save(automationEnabled, key: Keys.automationEnabled) } }
    var autoFetchEnabled: Bool { didSet { save(autoFetchEnabled, key: Keys.autoFetchEnabled) } }
    var autoRecommendEnabled: Bool { didSet { save(autoRecommendEnabled, key: Keys.autoRecommendEnabled) } }
    var lastAutoFetchAt: Date? { didSet { save(lastAutoFetchAt, key: Keys.lastAutoFetchAt) } }
    var lastAutoRecommendAt: Date? { didSet { save(lastAutoRecommendAt, key: Keys.lastAutoRecommendAt) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automationEnabled = defaults.object(forKey: Keys.automationEnabled) as? Bool ?? false
        autoFetchEnabled = defaults.object(forKey: Keys.autoFetchEnabled) as? Bool ?? true
        autoRecommendEnabled = defaults.object(forKey: Keys.autoRecommendEnabled) as? Bool ?? true
        lastAutoFetchAt = defaults.object(forKey: Keys.lastAutoFetchAt) as? Date
        lastAutoRecommendAt = defaults.object(forKey: Keys.lastAutoRecommendAt) as? Date
    }

    private func save(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: Date?, key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let automationEnabled = "automation.enabled"
        static let autoFetchEnabled = "automation.fetch.monthly.enabled"
        static let autoRecommendEnabled = "automation.recommend.daily.enabled"
        static let lastAutoFetchAt = "automation.fetch.monthly.lastRun"
        static let lastAutoRecommendAt = "automation.recommend.daily.lastRun"
    }
}
