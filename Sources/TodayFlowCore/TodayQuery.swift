import Foundation

/// Assembles the Today view (driver.md FR-10, FR-13).
///
/// Partitions the open items into overdue (pinned at top, red) and on-time, fetches the
/// "Done today" section, and computes the progress header (done / total, remaining,
/// overdue, and time left until end of business).
public struct TodayQuery: Sendable {
    /// Progress header values (driver.md FR-13).
    public struct Progress: Sendable {
        public var done: Int
        public var total: Int
        public var remaining: Int
        public var overdue: Int
        /// 0.0–1.0 fraction of today's tasks done.
        public var fraction: Double
        /// Seconds until end of business (clamped to ≥ 0).
        public var secondsUntilEOB: TimeInterval

        /// True when there is at least one task and none remain.
        public var isCleared: Bool { total > 0 && remaining == 0 }

        public init(
            done: Int,
            total: Int,
            remaining: Int,
            overdue: Int,
            fraction: Double,
            secondsUntilEOB: TimeInterval
        ) {
            self.done = done
            self.total = total
            self.remaining = remaining
            self.overdue = overdue
            self.fraction = fraction
            self.secondsUntilEOB = secondsUntilEOB
        }
    }

    public struct Result: Sendable {
        /// Open items past their `endAt`, in display order (pinned at the top).
        public var overdue: [WorkItem]
        /// Open items not yet past due, in display order.
        public var open: [WorkItem]
        /// Items completed on the day, in display order (the "Done today" section).
        public var doneToday: [WorkItem]
        public var progress: Progress

        /// All open items, overdue first, then on-time (each group in display order).
        public var all: [WorkItem] { overdue + open }
    }

    private let repository: any WorkItemRepository
    private let calendar: WorkCalendar

    public init(repository: any WorkItemRepository, calendar: WorkCalendar) {
        self.repository = repository
        self.calendar = calendar
    }

    public func execute(on day: Date, at: Date = .now) async -> Result {
        // Epics and projects are containers, not day work. Keeping them out
        // of the Today query also keeps the progress ring task-based.
        let open = await repository.todayItems(on: day, calendar: calendar)
            .filter { $0.kind == .task }
        let overdue = open.filter { $0.endAt < at }
        let onTime = open.filter { $0.endAt >= at }
        let doneToday = await repository.completedToday(on: day, calendar: calendar)
            .filter { $0.kind == .task }

        let done = doneToday.count
        let total = open.count + doneToday.count
        let progress = Progress(
            done: done,
            total: total,
            remaining: open.count,
            overdue: overdue.count,
            fraction: total == 0 ? 0 : Double(done) / Double(total),
            secondsUntilEOB: calendar.timeUntilEndOfBusiness(from: at)
        )
        return Result(overdue: overdue, open: onTime, doneToday: doneToday, progress: progress)
    }
}

public extension TodayQuery.Result {
    /// An empty, not-yet-loaded state (the Today view model's initial value).
    static let empty = TodayQuery.Result(
        overdue: [],
        open: [],
        doneToday: [],
        progress: TodayQuery.Progress(
            done: 0,
            total: 0,
            remaining: 0,
            overdue: 0,
            fraction: 0,
            secondsUntilEOB: 0
        )
    )
}
