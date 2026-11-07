import Foundation

/// A unit of work — an Epic, Project, Task, or Subtask (driver.md §2).
///
/// All four kinds share one shape; `kind` and the optional `parentId` express the
/// hierarchy. Every kind can stand alone (`parentId == nil`).
/// How a task repeats after it is completed. Deliberately small and
/// understandable: five presets, no custom interval or end-date rules.
public enum Recurrence: String, Codable, CaseIterable, Hashable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly

    public var label: String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }

    public var shortLabel: String {
        switch self {
        case .daily: return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// The next start after `date`, keeping the same time of day.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            guard var next = calendar.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            while calendar.isDateInWeekend(next) {
                guard let following = calendar.date(byAdding: .day, value: 1, to: next) else {
                    return nil
                }
                next = following
            }
            return next
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

public struct WorkItem: Identifiable, Hashable, Sendable, Codable {
    /// The four work-item kinds, from broadest to most granular.
    public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
        case epic
        case project
        case task
        case subtask

        public var label: String { rawValue.capitalized }

        /// Kinds that may be the parent of this kind (driver.md §2 hierarchy table:
        /// Epic → Projects → Tasks → Subtasks; every kind can also stand alone, hence
        /// the `nil` in each set).
        public var allowedParentKinds: Set<Kind?> {
            switch self {
            case .epic:     return [nil]
            case .project:  return [.epic, nil]
            case .task:     return [.project, nil]
            case .subtask:  return [.task, nil]
            }
        }
    }

    public var id: UUIDv7
    public var kind: Kind
    /// 1–200 characters (driver.md §2).
    public var title: String
    /// The parent's `id`, or `nil` for a top-level / standalone item.
    public var parentId: UUIDv7?
    /// Markdown body.
    public var descriptionMd: String
    /// A short summary of the task or its source (for example an email),
    /// produced on-device or by the configured AI endpoint.
    public var summary: String
    public var status: Status
    public var priority: Priority
    /// How this item repeats after completion, or `nil` for one-off work.
    public var recurrence: Recurrence?
    /// When the work is scheduled to start (defaults to the drop/capture time).
    public var startAt: Date
    /// When the work is due (defaults per `WorkCalendar.defaultEndAt`).
    public var endAt: Date
    /// Optional effort estimate in minutes, used by the daily load meter.
    public var estimatedMinutes: Int?
    /// Set when the item transitions to `.done`.
    public var completedAt: Date?
    /// Fractional-index sort key within its parent's children (driver.md §2).
    public var displayOrder: String
    /// A color identifier (hex or a named theme color), or `nil`.
    public var color: String?
    public var tags: [String]
    // Sync-ready conventions (driver.md §6).
    public var createdAt: Date
    public var updatedAt: Date
    /// Soft-delete timestamp; `nil` while the item is live.
    public var deletedAt: Date?
    /// Monotonic revision, bumped on every change for sync merging.
    public var version: Int
    /// The device that last wrote this row.
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        kind: Kind = .task,
        title: String,
        parentId: UUIDv7? = nil,
        descriptionMd: String = "",
        summary: String = "",
        status: Status = .todo,
        priority: Priority = .default,
        recurrence: Recurrence? = nil,
        startAt: Date = .now,
        endAt: Date = .now,
        estimatedMinutes: Int? = nil,
        completedAt: Date? = nil,
        displayOrder: String = FractionalIndex.bottom,
        color: String? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.parentId = parentId
        self.descriptionMd = descriptionMd
        self.summary = summary
        self.status = status
        self.priority = priority
        self.recurrence = recurrence
        self.startAt = startAt
        self.endAt = endAt
        self.estimatedMinutes = estimatedMinutes
        self.completedAt = completedAt
        self.displayOrder = displayOrder
        self.color = color
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.deviceId = deviceId
    }

    // MARK: - Derived state

    /// True if the item has been soft-deleted.
    public var isDeleted: Bool { deletedAt != nil }

    /// True if the item is in a terminal state (done or cancelled).
    public var isComplete: Bool { status.isComplete }

    /// Bump the revision and stamp the update time. Returns the updated copy.
    public func touching(_ now: Date = .now) -> WorkItem {
        var copy = self
        copy.version += 1
        copy.updatedAt = now
        return copy
    }
}
