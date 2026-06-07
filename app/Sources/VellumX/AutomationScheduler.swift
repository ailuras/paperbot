import Foundation
import Observation

@MainActor
final class AutomationScheduler {
    private let preferences: AutomationPreferences
    private let workflows: PaperWorkflowService
    private let store: PaperStore
    private let calendar: Calendar
    private var timer: Timer?
    private var isChecking = false

    init(
        preferences: AutomationPreferences = .shared,
        workflows: PaperWorkflowService = .shared,
        store: PaperStore = .shared,
        calendar: Calendar = .current
    ) {
        self.preferences = preferences
        self.workflows = workflows
        self.store = store
        self.calendar = calendar
    }

    func start() {
        guard timer == nil else { return }
        observePreferences()
        Task { @MainActor in
            await checkAndRun()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkAndRun()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func checkAndRun(now: Date = Date()) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        guard preferences.automationEnabled else { return }

        if preferences.autoFetchEnabled,
           Self.needsMonthlyRun(lastRun: preferences.lastAutoFetchAt, now: now, calendar: calendar),
           Self.shouldRunAtScheduledTime(
               requiredDay: preferences.fetchDay,
               hour: preferences.fetchHour,
               minute: preferences.fetchMinute,
               now: now, calendar: calendar
           ) {
            let result = await workflows.fetchPapers(notify: false)
            if result.didRun {
                preferences.lastAutoFetchAt = Date()
            }
        }

        if preferences.autoRecommendEnabled,
           Self.needsDailyRun(lastRun: preferences.lastAutoRecommendAt, now: now, calendar: calendar),
           Self.shouldRunAtScheduledTime(
               hour: preferences.recommendHour,
               minute: preferences.recommendMinute,
               now: now, calendar: calendar
           ) {
            if hasRecommendationToday(now: now) {
                preferences.lastAutoRecommendAt = now
            } else {
                let result = await workflows.recommendPapers(notify: false)
                if result.didRun {
                    preferences.lastAutoRecommendAt = Date()
                }
            }
        }
    }

    private func observePreferences() {
        withObservationTracking {
            _ = preferences.automationEnabled
            _ = preferences.autoFetchEnabled
            _ = preferences.autoRecommendEnabled
            _ = preferences.recommendHour
            _ = preferences.recommendMinute
            _ = preferences.fetchDay
            _ = preferences.fetchHour
            _ = preferences.fetchMinute
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observePreferences()
                await self?.checkAndRun()
            }
        }
    }

    private func hasRecommendationToday(now: Date) -> Bool {
        store.papers.contains { paper in
            paper.isRecommended && paper.recommendedAt.map {
                calendar.isDate($0, inSameDayAs: now)
            } == true
        }
    }

    nonisolated static func needsDailyRun(lastRun: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastRun else { return true }
        return !calendar.isDate(lastRun, inSameDayAs: now)
    }

    nonisolated static func needsMonthlyRun(lastRun: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastRun else { return true }
        let last = calendar.dateComponents([.era, .year, .month], from: lastRun)
        let current = calendar.dateComponents([.era, .year, .month], from: now)
        return last.era != current.era || last.year != current.year || last.month != current.month
    }

    /// Returns true when `now` has reached or passed the scheduled parameters.
    /// - `requiredDay`: -1 means "any day" (used only for monthly fetch).
    /// - `hour`: -1 means "any time" (returns true immediately).
    /// - `minute`: ignored when hour is -1; -1 behaves as 0.
    nonisolated static func shouldRunAtScheduledTime(
        requiredDay: Int = -1,
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        guard hour >= 0 else { return true }
        let dc = calendar.dateComponents([.day, .hour, .minute], from: now)
        let nowDay = dc.day ?? 0
        let nowHour = dc.hour ?? 0
        let nowMinute = dc.minute ?? 0

        if requiredDay >= 0 {
            if nowDay > requiredDay { return true }
            guard nowDay == requiredDay else { return false }
        }

        if nowHour > hour { return true }
        guard nowHour == hour else { return false }
        let m = minute < 0 ? 0 : minute
        return nowMinute >= m
    }
}
