import XCTest
@testable import VellumX

final class AutomationSchedulerTests: XCTestCase {
    func testDailyRunIsDueOnlyAcrossCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let morning = date("2026-06-07T09:00:00Z")
        let evening = date("2026-06-07T20:00:00Z")
        let tomorrow = date("2026-06-08T01:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: nil, now: morning, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsDailyRun(lastRun: morning, now: evening, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsDailyRun(lastRun: evening, now: tomorrow, calendar: calendar))
    }

    func testMonthlyRunIsDueOnlyAcrossCalendarMonths() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let earlyJune = date("2026-06-01T08:00:00Z")
        let lateJune = date("2026-06-30T23:00:00Z")
        let july = date("2026-07-01T00:00:00Z")

        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: nil, now: earlyJune, calendar: calendar))
        XCTAssertFalse(AutomationScheduler.needsMonthlyRun(lastRun: earlyJune, now: lateJune, calendar: calendar))
        XCTAssertTrue(AutomationScheduler.needsMonthlyRun(lastRun: lateJune, now: july, calendar: calendar))
    }

    private func date(_ isoString: String) -> Date {
        ISO8601DateFormatter().date(from: isoString)!
    }
}
