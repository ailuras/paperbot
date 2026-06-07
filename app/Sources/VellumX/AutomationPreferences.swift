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

    /// -1 = anytime (current immediate-run behavior).
    var recommendHour: Int { didSet {
        save(recommendHour, key: Keys.recommendHour)
        if recommendHour >= 0, oldValue < 0, recommendMinute < 0 { recommendMinute = 0 }
    } }
    var recommendMinute: Int { didSet { save(recommendMinute, key: Keys.recommendMinute) } }
    /// -1 = anytime (current immediate-run behavior). 1-28 only in UI to avoid
    /// silent misfires in months shorter than 29-31.
    var fetchDay: Int { didSet {
        save(fetchDay, key: Keys.fetchDay)
        if fetchDay > 0, oldValue < 0 {
            if fetchHour < 0 { fetchHour = 9 }
            if fetchMinute < 0 { fetchMinute = 0 }
        }
    } }
    var fetchHour: Int { didSet { save(fetchHour, key: Keys.fetchHour) } }
    var fetchMinute: Int { didSet { save(fetchMinute, key: Keys.fetchMinute) } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automationEnabled = defaults.object(forKey: Keys.automationEnabled) as? Bool ?? false
        autoFetchEnabled = defaults.object(forKey: Keys.autoFetchEnabled) as? Bool ?? true
        autoRecommendEnabled = defaults.object(forKey: Keys.autoRecommendEnabled) as? Bool ?? true
        lastAutoFetchAt = defaults.object(forKey: Keys.lastAutoFetchAt) as? Date
        lastAutoRecommendAt = defaults.object(forKey: Keys.lastAutoRecommendAt) as? Date
        recommendHour = defaults.object(forKey: Keys.recommendHour) as? Int ?? -1
        recommendMinute = defaults.object(forKey: Keys.recommendMinute) as? Int ?? -1
        fetchDay = defaults.object(forKey: Keys.fetchDay) as? Int ?? -1
        fetchHour = defaults.object(forKey: Keys.fetchHour) as? Int ?? -1
        fetchMinute = defaults.object(forKey: Keys.fetchMinute) as? Int ?? -1
    }

    private func save(_ value: Bool, key: String) {
        defaults.set(value, forKey: key)
    }

    private func save(_ value: Int, key: String) {
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
        static let recommendHour = "automation.recommend.daily.hour"
        static let recommendMinute = "automation.recommend.daily.minute"
        static let fetchDay = "automation.fetch.monthly.day"
        static let fetchHour = "automation.fetch.monthly.hour"
        static let fetchMinute = "automation.fetch.monthly.minute"
    }
}
