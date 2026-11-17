import Foundation

/// The rules a task's start and due times follow everywhere they are edited.
public enum TaskSchedule {
    /// How far a due time is pushed past the start when it would otherwise
    /// land on or before it.
    public static let defaultDuration: TimeInterval = 60 * 60

    /// The smallest gap the due picker allows after the start.
    public static let minimumDuration: TimeInterval = 60

    /// The top of the hour `date` falls in: the default start of a new task.
    public static func startOfHour(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// `due` when it is after `start`; otherwise one hour after `start`.
    /// A task is never due at or before the moment it starts.
    public static func dueAfterStart(start: Date, due: Date) -> Date {
        due > start ? due : start.addingTimeInterval(defaultDuration)
    }
}
