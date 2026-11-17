import Foundation

/// How close a task is to its due time, for the on-screen due-soon popup.
/// The raw value is the number of hours left when the stage begins.
public enum DueNudgeStage: Int, Codable, CaseIterable, Sendable, Comparable {
    case oneHour = 1
    case fiveHours = 5
    case twelveHours = 12

    public var threshold: TimeInterval { TimeInterval(rawValue) * 3600 }

    /// A tighter deadline sorts first.
    public static func < (lhs: DueNudgeStage, rhs: DueNudgeStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The stage for the time left, or `nil` when the task is more than
    /// twelve hours away or already past due.
    public static func stage(remaining: TimeInterval) -> DueNudgeStage? {
        guard remaining > 0 else { return nil }
        return allCases.sorted().first { remaining <= $0.threshold }
    }
}

/// One popup to show: this task just moved into this stage.
public struct DueNudge: Hashable, Sendable, Identifiable {
    public let itemId: UUIDv7
    public let title: String
    public let dueAt: Date
    public let stage: DueNudgeStage
    public var id: String { "\(itemId)-\(stage.rawValue)" }

    public init(itemId: UUIDv7, title: String, dueAt: Date, stage: DueNudgeStage) {
        self.itemId = itemId
        self.title = title
        self.dueAt = dueAt
        self.stage = stage
    }
}

/// Decides when a task earns a due-soon popup: once as it crosses into the
/// 12-hour, 5-hour and 1-hour windows before its due time.
public struct DueNudgePlanner: Sendable {
    /// The last stage seen for a task, tied to the due time it was seen with
    /// so that rescheduling a task starts it over.
    public struct Seen: Codable, Hashable, Sendable {
        public var dueAt: Date
        /// `nil` while the task was still more than twelve hours away.
        public var stage: DueNudgeStage?

        public init(dueAt: Date, stage: DueNudgeStage?) {
            self.dueAt = dueAt
            self.stage = stage
        }
    }

    public typealias Memory = [String: Seen]

    /// A task this new is not nagged about on first sight: its author just
    /// chose the due time.
    public var newTaskGrace: TimeInterval = 5 * 60

    public init() {}

    /// Returns the popups to show now, most urgent first, and updates
    /// `memory` so each stage fires once per task and due time.
    ///
    /// A task seen for the first time is only recorded, not announced, so
    /// opening the app does not replay every task due today. The exception is
    /// a task already inside its last hour.
    public func plan(
        items: [WorkItem],
        now: Date,
        memory: inout Memory
    ) -> [DueNudge] {
        var nudges: [DueNudge] = []
        var next: Memory = [:]

        for item in items
        where item.kind == .task && !item.isDeleted && !item.status.isTerminal {
            let key = item.id.description
            let current = DueNudgeStage.stage(remaining: item.endAt.timeIntervalSince(now))
            defer { next[key] = Seen(dueAt: item.endAt, stage: current) }

            guard let current else { continue }
            let previous = memory[key].flatMap { $0.dueAt == item.endAt ? $0 : nil }

            let shouldFire: Bool
            if let previous {
                // Fire only when the task moved into a tighter stage.
                shouldFire = previous.stage.map { current < $0 } ?? true
            } else {
                shouldFire = current == .oneHour
                    && now.timeIntervalSince(item.createdAt) > newTaskGrace
            }
            if shouldFire {
                nudges.append(
                    DueNudge(itemId: item.id, title: item.title, dueAt: item.endAt, stage: current)
                )
            }
        }

        memory = next
        return nudges.sorted {
            if $0.stage != $1.stage { return $0.stage < $1.stage }
            return $0.dueAt < $1.dueAt
        }
    }
}
