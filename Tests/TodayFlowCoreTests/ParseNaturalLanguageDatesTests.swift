import Foundation
import Testing
@testable import TodayFlowCore

struct ParseNaturalLanguageDatesTests {
    /// Pinned to the fixed UTC test calendar. Exercises the regex-fallback
    /// path (word-numeral relatives, midnight, noon), which resolves
    /// against the injected `now` — fully deterministic.
    private func pinned() -> ParseNaturalLanguageDates {
        ParseNaturalLanguageDates(calendar: TestDates.calendar, workCalendar: TestDates.workCalendar)
    }

    /// Runs on the real calendar. Exercises the `NSDataDetector` path, which
    /// always resolves against the real current date, so expectations are
    /// derived from `Date.now` rather than pinned.
    private func live() -> ParseNaturalLanguageDates {
        ParseNaturalLanguageDates(calendar: .current, workCalendar: .standard)
    }

    // MARK: - No matches

    @Test func emptyTextReturnsEmpty() {
        #expect(pinned().parse("", at: TestDates.monday).isEmpty)
    }

    @Test func noDateExpressionReturnsEmpty() {
        #expect(pinned().parse("call Sam about the budget", at: TestDates.monday).isEmpty)
    }

    // MARK: - Detector path (real now)

    @Test func combinedTodayTime() {
        let now = Date.now
        let results = live().parse("today 3pm", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        #expect(cal.isDate(results[0].start, inSameDayAs: now))
        #expect(cal.component(.hour, from: results[0].start) == 15)
        #expect(cal.component(.minute, from: results[0].start) == 0)
        #expect(cal.isDate(results[0].end, inSameDayAs: results[0].start))
        #expect(cal.component(.hour, from: results[0].end) == 17)
    }

    @Test func timeOnlyRollsForwardWhenPast() {
        let now = Date.now
        let results = live().parse("3pm", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        let today15 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now)!
        let expectedDay = today15 < now
            ? cal.date(byAdding: .day, value: 1, to: today15)!
            : today15
        #expect(cal.isDate(results[0].start, inSameDayAs: expectedDay))
        #expect(cal.component(.hour, from: results[0].start) == 15)
        #expect(cal.component(.minute, from: results[0].start) == 0)
    }

    @Test func timeOnly24hClock() {
        let now = Date.now
        let results = live().parse("14:30", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        let today1430 = cal.date(bySettingHour: 14, minute: 30, second: 0, of: now)!
        let expectedDay = today1430 < now
            ? cal.date(byAdding: .day, value: 1, to: today1430)!
            : today1430
        #expect(cal.isDate(results[0].start, inSameDayAs: expectedDay))
        #expect(cal.component(.hour, from: results[0].start) == 14)
        #expect(cal.component(.minute, from: results[0].start) == 30)
    }

    @Test func dateOnlyDefaultsToBusinessStart() {
        let now = Date.now
        let results = live().parse("tomorrow", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        let expectedDay = cal.date(byAdding: .day, value: 1, to: now)!
        #expect(cal.isDate(results[0].start, inSameDayAs: expectedDay))
        #expect(cal.component(.hour, from: results[0].start) == 9)
        #expect(cal.component(.minute, from: results[0].start) == 0)
        #expect(cal.isDate(results[0].end, inSameDayAs: results[0].start))
        #expect(cal.component(.hour, from: results[0].end) == 17)
    }

    @Test func nextWeekdayResolvesToNextWeek() {
        let now = Date.now
        let results = live().parse("next Friday", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        let start = results[0].start
        #expect(cal.component(.weekday, from: start) == 6) // Friday
        #expect(cal.component(.hour, from: start) == 9)
        let daysAhead = cal.dateComponents(
            [.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: start)
        ).day ?? 0
        #expect((2...11).contains(daysAhead))
    }

    @Test func numericRelativeUsesDetector() {
        let now = Date.now
        let results = live().parse("in 3 days", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        #expect(cal.component(.hour, from: results[0].start) == 9)
        let daysAhead = cal.dateComponents(
            [.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: results[0].start)
        ).day ?? 0
        #expect((2...4).contains(daysAhead))
    }

    @Test func tonightResolvesToEvening() {
        let now = Date.now
        let results = live().parse("tonight", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        #expect(cal.isDate(results[0].start, inSameDayAs: now))
        #expect(cal.component(.hour, from: results[0].start) >= 17)
    }

    @Test func dateAndTimeWithCommaPairIntoOneResult() {
        let now = Date.now
        let results = live().parse("today, 3pm", at: now)
        #expect(results.count == 1)
        let cal = Calendar.current
        #expect(cal.isDate(results[0].start, inSameDayAs: now))
        #expect(cal.component(.hour, from: results[0].start) == 15)
        #expect(cal.component(.minute, from: results[0].start) == 0)
    }

    @Test func multipleExpressionsReturnInOrder() {
        let now = Date.now
        let results = live().parse("today 3pm and tomorrow", at: now)
        #expect(results.count == 2)
        let cal = Calendar.current
        #expect(cal.component(.hour, from: results[0].start) == 15)
        #expect(cal.isDate(results[0].start, inSameDayAs: now))
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        #expect(cal.isDate(results[1].start, inSameDayAs: tomorrow))
        #expect(cal.component(.hour, from: results[1].start) == 9)
    }

    @Test func endClampedToStartWhenStartIsAfterEOB() {
        let now = Date.now
        let results = live().parse("6pm", at: now)
        #expect(results.count == 1)
        #expect(results[0].end == results[0].start)
    }

    // MARK: - Fallback path (pinned now)

    @Test func wordNumeralRelativeIsPinned() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 0) // Monday
        let results = pinned().parse("in two days", at: now)
        #expect(results.count == 1)
        #expect(results[0].start == TestDates.date(2026, 1, 7, hour: 9)) // Wednesday 09:00
        #expect(results[0].end == TestDates.date(2026, 1, 7, hour: 17))
    }

    @Test func midnightRollsToNextDayWhenPast() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 0) // Monday
        let results = pinned().parse("midnight", at: now)
        #expect(results.count == 1)
        #expect(results[0].start == TestDates.tuesday) // Tuesday 00:00
        #expect(results[0].end == TestDates.date(2026, 1, 6, hour: 17))
    }

    @Test func noonStaysTodayWhenFuture() {
        let now = TestDates.date(2026, 1, 5, hour: 10, minute: 0) // Monday
        let results = pinned().parse("noon", at: now)
        #expect(results.count == 1)
        #expect(results[0].start == TestDates.date(2026, 1, 5, hour: 12))
        #expect(results[0].end == TestDates.date(2026, 1, 5, hour: 17))
    }
}
