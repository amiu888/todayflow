import Foundation

/// The user's working-hours model, used to compute default task end times and
/// "end of business" (driver.md §2, §11 acceptance criteria).
///
/// It is a value type so it can be injected and faked in tests (fixed calendar,
/// time zone, and hours). Weekdays use `Calendar.Component.weekday`, where
/// 1 = Sunday … 7 = Saturday (so 2–6 = Monday–Friday).
public struct WorkCalendar: Sendable {
    /// Hour of day work starts (e.g. 9.0 = 09:00).
    public var startHour: Double
    /// Hour of day work ends (e.g. 17.0 = 17:00) — "end of business".
    public var endHour: Double
    /// Weekdays that are working days (Calendar weekday: 2 = Mon … 6 = Fri).
    public var workWeekdays: Set<Int>
    /// Calendar used for all date math (time zone, weekday layout).
    public let calendar: Calendar

    public init(
        startHour: Double = 9,
        endHour: Double = 17,
        workWeekdays: Set<Int> = [2, 3, 4, 5, 6],
        calendar: Calendar = .current
    ) {
        self.startHour = startHour
        self.endHour = endHour
        self.workWeekdays = workWeekdays
        self.calendar = calendar
    }

    /// The standard 09:00–17:00, Monday–Friday calendar.
    public static let standard = WorkCalendar()

    /// True if the day containing `date` is a working day.
    public func isWorkingDay(_ date: Date) -> Bool {
        workWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// The end-of-business instant on the calendar day that contains `date`.
    public func endOfBusiness(for date: Date) -> Date {
        calendar.date(bySettingHour: Int(endHour), minute: 0, second: 0, of: date) ?? date
    }

    /// The start-of-business instant on the calendar day that contains `date`.
    public func startOfBusiness(for date: Date) -> Date {
        calendar.date(bySettingHour: Int(startHour), minute: 0, second: 0, of: date) ?? date
    }

    /// The first instant of the next calendar day. Used by the Today query:
    /// "startAt ≤ end of today" includes after-hours captures and late tasks.
    public func endOfDay(for date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
    }

    /// Default end time for a task created at `createdAt` (driver.md §2):
    /// - if `createdAt` falls before today's EOB on a working day → today's EOB
    /// - otherwise (after hours, or a non-working day) → the next working day's EOB
    ///
    /// e.g. dropped 10:42 on a weekday → 17:00 today; dropped 18:30 → 17:00 next business day.
    public func defaultEndAt(createdAt: Date) -> Date {
        let todayEOB = endOfBusiness(for: createdAt)
        if isWorkingDay(createdAt), createdAt < todayEOB {
            return todayEOB
        }
        // Walk forward day by day from the day after `createdAt` to the next working day.
        var day = calendar.startOfDay(for: createdAt)
        while true {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            if isWorkingDay(next) {
                return endOfBusiness(for: next)
            }
            day = next
        }
    }

    /// Seconds from `now` until end of business on `now`'s day (clamped to ≥ 0).
    public func timeUntilEndOfBusiness(from now: Date) -> TimeInterval {
        max(0, endOfBusiness(for: now).timeIntervalSince(now))
    }
}
