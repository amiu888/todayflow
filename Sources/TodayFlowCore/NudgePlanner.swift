import Foundation

/// Computes the local notifications for the rest of the day (driver.md FR-42).
///
/// Pure and deterministic: the app adapter (`NotificationController`) turns
/// these values into `UNNotificationRequest`s; tests assert the schedule with a
/// fixed clock and calendar. Two kinds are planned:
///
/// - **End-of-day nudges** at a configurable lead before end of business
///   (defaults: 2 h and 30 min), only while tasks remain.
/// - **Task reminders** at a lead before each task's own `endAt`
///   (default: 30 min), skipping tasks already overdue.
///
/// Nudges in the past are never returned, so a reschedule after completing work
/// cannot resurrect an old notification.
public struct NudgePlanner: Sendable {
    /// One notification to schedule.
    public struct Nudge: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            /// The daily summary before end of business.
            case endOfDay(lead: TimeInterval)
            /// A reminder about one task.
            case task(UUIDv7)
        }

        /// Stable identifier, so rescheduling replaces rather than duplicates.
        public let id: String
        public let kind: Kind
        public let fireAt: Date
        public let title: String
        public let body: String
        /// The task the notification's actions apply to, when there is one.
        public let itemId: UUIDv7?
        /// P1 reminders break through Focus (FR-44).
        public let priority: Priority

        public var isUrgent: Bool { priority == .urgent }

        public init(
            id: String,
            kind: Kind,
            fireAt: Date,
            title: String,
            body: String,
            itemId: UUIDv7?,
            priority: Priority
        ) {
            self.id = id
            self.kind = kind
            self.fireAt = fireAt
            self.title = title
            self.body = body
            self.itemId = itemId
            self.priority = priority
        }
    }

    /// Leads before end of business. Driver defaults: 2 hours and 30 minutes.
    public var endOfDayLeads: [TimeInterval]
    /// Lead before a task's `endAt`.
    public var taskLead: TimeInterval

    public init(
        endOfDayLeads: [TimeInterval] = [2 * 3_600, 30 * 60],
        taskLead: TimeInterval = 30 * 60
    ) {
        self.endOfDayLeads = endOfDayLeads
        self.taskLead = taskLead
    }

    /// The schedule for `openItems` at `now`.
    public func plan(
        openItems: [WorkItem],
        calendar: WorkCalendar,
        now: Date
    ) -> [Nudge] {
        let open = openItems
            .filter { !$0.isDeleted && !$0.status.isTerminal }
            .sorted { $0.endAt < $1.endAt }
        guard !open.isEmpty else { return [] }

        var nudges: [Nudge] = []
        let eob = calendar.endOfBusiness(for: now)

        for lead in endOfDayLeads {
            let fireAt = eob.addingTimeInterval(-lead)
            guard fireAt > now else { continue }
            let time = eob.formatted(date: .omitted, time: .shortened)
            nudges.append(
                Nudge(
                    id: "eod.\(Int(lead))",
                    kind: .endOfDay(lead: lead),
                    fireAt: fireAt,
                    title: "End of day approaching",
                    body: "\(open.count) task\(open.count == 1 ? "" : "s") left · business day ends at \(time)",
                    // The summary is about the day, not one task: tapping it
                    // opens Today instead of showing task actions.
                    itemId: nil,
                    priority: open.map(\.priority).min() ?? .normal
                )
            )
        }

        for item in open {
            let fireAt = item.endAt.addingTimeInterval(-taskLead)
            guard fireAt > now else { continue }
            let due = item.endAt.formatted(date: .omitted, time: .shortened)
            nudges.append(
                Nudge(
                    id: "task.\(item.id)",
                    kind: .task(item.id),
                    fireAt: fireAt,
                    title: item.title,
                    body: "Due at \(due)",
                    itemId: item.id,
                    priority: item.priority
                )
            )
        }

        return nudges.sorted {
            if $0.fireAt != $1.fireAt { return $0.fireAt < $1.fireAt }
            return $0.id < $1.id
        }
    }
}
