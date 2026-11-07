import Foundation
import Testing
@testable import TodayFlowCore

struct RecurrenceTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour
            )
        )!
    }

    @Test func dailyAddsOneDay() {
        let start = date(2026, 11, 3)
        #expect(Recurrence.daily.nextStart(after: start, calendar: calendar) == date(2026, 11, 4))
    }

    @Test func weekdaysSkipsTheWeekend() {
        let friday = date(2026, 11, 6)
        #expect(Recurrence.weekdays.nextStart(after: friday, calendar: calendar) == date(2026, 11, 9))
    }

    @Test func weeklyAddsSevenDays() {
        let start = date(2026, 11, 3)
        #expect(Recurrence.weekly.nextStart(after: start, calendar: calendar) == date(2026, 11, 10))
    }

    @Test func monthlyClampsToTheEndOfTheMonth() {
        let january31 = date(2026, 1, 31)
        #expect(Recurrence.monthly.nextStart(after: january31, calendar: calendar) == date(2026, 2, 28))
    }

    @Test func yearlyHandlesLeapDay() {
        let leapDay = date(2028, 2, 29)
        #expect(Recurrence.yearly.nextStart(after: leapDay, calendar: calendar) == date(2029, 2, 28))
    }
}
