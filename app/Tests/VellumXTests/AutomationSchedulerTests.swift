import XCTest
@testable import VellumX

final class AutomationSchedulerTests: XCTestCase {
    func testDailyRunIsDueOnlyAcrossCalendarDays() {
        let calendar = utcCalendar()
        let morning = date("2026-06-07T09:00:00Z")
        let evening = date("2026-06-07T20:00:00Z")
        let tomorrow = date("2026-06-08T01:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: nil, now: morning, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsDailyRun(lastRun: morning, now: evening, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: evening, now: tomorrow, calendar: calendar))
    }

    func testMonthlyRunIsDueOnlyAcrossCalendarMonths() {
        let calendar = utcCalendar()
        let earlyJune = date("2026-06-01T08:00:00Z")
        let lateJune = date("2026-06-30T23:00:00Z")
        let july = date("2026-07-01T00:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: nil, now: earlyJune, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsMonthlyRun(lastRun: earlyJune, now: lateJune, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: lateJune, now: july, calendar: calendar))
    }

    // MARK: - shouldRunAtScheduledTime

    func testScheduledTimeReturnsTrueWhenNoHourConfigured() {
        let calendar = utcCalendar()
        let now = date("2026-06-07T10:30:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            hour: -1, minute: -1, now: now, calendar: calendar))
    }

    func testScheduledTimeBeforeConfiguredHour() {
        let calendar = utcCalendar()
        let now = date("2026-06-07T13:30:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            hour: 14, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimeAtExactHourAndMinute() {
        let calendar = utcCalendar()
        let now = date("2026-06-07T14:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            hour: 14, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimeAfterConfiguredHour() {
        let calendar = utcCalendar()
        let now = date("2026-06-07T14:30:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            hour: 14, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimeBeforeConfiguredMinute() {
        let calendar = utcCalendar()
        let now = date("2026-06-07T14:15:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            hour: 14, minute: 30, now: now, calendar: calendar))
    }

    // MARK: Day + time

    func testScheduledTimeBeforeRequiredDay() {
        let calendar = utcCalendar()
        let now = date("2026-06-10T14:30:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            requiredDay: 15, hour: 9, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimeOnRequiredDayBeforeTime() {
        let calendar = utcCalendar()
        let now = date("2026-06-15T08:00:00Z")
        XCTAssertFalse(AutomationScheduler.shouldRunAtScheduledTime(
            requiredDay: 15, hour: 9, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimeOnRequiredDayAtTime() {
        let calendar = utcCalendar()
        let now = date("2026-06-15T09:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            requiredDay: 15, hour: 9, minute: 0, now: now, calendar: calendar))
    }

    func testScheduledTimePastRequiredDayRunsImmediately() {
        let calendar = utcCalendar()
        let now = date("2026-06-16T08:00:00Z")
        XCTAssertTrue(AutomationScheduler.shouldRunAtScheduledTime(
            requiredDay: 15, hour: 9, minute: 0, now: now, calendar: calendar))
    }

    // MARK: - Helpers

    private func date(_ isoString: String) -> Date {
        ISO8601DateFormatter().date(from: isoString)!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
