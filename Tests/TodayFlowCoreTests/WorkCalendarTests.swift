import Foundation
import Testing
@testable import TodayFlowCore

struct WorkCalendarTests {
    private let cal = TestDates.workCalendar

    @Test func weekdaysAreWorkingDays() {
        #expect(cal.isWorkingDay(TestDates.monday))
        #expect(cal.isWorkingDay(TestDates.friday))
        #expect(!cal.isWorkingDay(TestDates.saturday))
        #expect(!cal.isWorkingDay(TestDates.sunday))
    }

    @Test func endOfBusinessIs1700ThatDay() {
        let eob = cal.endOfBusiness(for: TestDates.date(2026, 1, 5, hour: 10, minute: 42))
        #expect(eob == TestDates.date(2026, 1, 5, hour: 17))
    }

    @Test func defaultEndAtMiddayWeekdayIsTodayEOB() {
        // Acceptance: dropped 10:42 on a weekday → 17:00 today.
        let created = TestDates.date(2026, 1, 5, hour: 10, minute: 42) // Monday
        #expect(cal.defaultEndAt(createdAt: created) == TestDates.date(2026, 1, 5, hour: 17))
    }

    @Test func defaultEndAtAfterHoursIsNextBusinessDay() {
        // Acceptance: dropped 18:30 (after hours) → next business day 17:00.
        let created = TestDates.date(2026, 1, 5, hour: 18, minute: 30) // Monday
        #expect(cal.defaultEndAt(createdAt: created) == TestDates.date(2026, 1, 6, hour: 17)) // Tuesday
    }

    @Test func defaultEndAtFridayAfterHoursSkipsWeekend() {
        let created = TestDates.date(2026, 1, 9, hour: 18, minute: 30) // Friday
        #expect(cal.defaultEndAt(createdAt: created) == TestDates.date(2026, 1, 12, hour: 17)) // Monday
    }

    @Test func defaultEndAtOnWeekendIsMonday() {
        let created = TestDates.date(2026, 1, 10, hour: 12) // Saturday
        #expect(cal.defaultEndAt(createdAt: created) == TestDates.date(2026, 1, 12, hour: 17)) // Monday
    }

    @Test func timeUntilEndOfBusiness() {
        let now = TestDates.date(2026, 1, 5, hour: 15) // Monday 15:00
        #expect(cal.timeUntilEndOfBusiness(from: now) == 2 * 3600) // 2h until 17:00
    }

    @Test func timeUntilEndOfBusinessClampedAtZero() {
        let now = TestDates.date(2026, 1, 5, hour: 18) // Monday 18:00, past EOB
        #expect(cal.timeUntilEndOfBusiness(from: now) == 0)
    }
}
