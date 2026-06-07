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
           Self.needsMonthlyRun(lastRun: preferences.lastAutoFetchAt, now: now, calendar: calendar) {
            let result = await workflows.fetchPapers(notify: false)
            if result.didRun {
                preferences.lastAutoFetchAt = Date()
            }
        }

        if preferences.autoRecommendEnabled,
           Self.needsDailyRun(lastRun: preferences.lastAutoRecommendAt, now: now, calendar: calendar) {
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
}
