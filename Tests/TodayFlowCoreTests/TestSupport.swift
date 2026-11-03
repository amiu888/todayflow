import Foundation
import TodayFlowCore

/// Deterministic date helpers for tests.
///
/// Uses a fixed Gregorian calendar in UTC (no DST) so weekday and hour math is stable
/// regardless of the machine's local time zone or the instant the suite runs.
///
/// Reference weekdays (UTC): 2026-01-05 is a Monday.
enum TestDates {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// A `WorkCalendar` bound to the fixed test calendar (09:00–17:00, Mon–Fri).
    static var workCalendar: WorkCalendar {
        WorkCalendar(calendar: calendar)
    }

    /// Build a `Date` from components in the fixed calendar.
    static func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute, second: second))!
    }

    static let monday = date(2026, 1, 5)
    static let tuesday = date(2026, 1, 6)
    static let friday = date(2026, 1, 9)
    static let saturday = date(2026, 1, 10)
    static let sunday = date(2026, 1, 11)
}
