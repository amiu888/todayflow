import Foundation

/// Creates a work item with the app's default dates and ordering (driver.md §11).
///
/// - `endAt` defaults to the `WorkCalendar` end-of-business for the start day
///   (dropped 10:42 on a weekday → 17:00 today; dropped 18:30 → next business day 17:00).
/// - `displayOrder` is appended after the last existing sibling.
/// - The hierarchy is validated against `WorkItem.Kind.allowedParentKinds`.
public struct CreateTask: Sendable {
    public struct Input {
        public enum Placement: Sendable {
            /// Append after the last sibling (default, used for subtasks).
            case bottom
            /// Insert before the first sibling so a new capture is visible.
            case top
        }

        public var kind: WorkItem.Kind
        public var title: String
        public var descriptionMd: String
        public var parentId: UUIDv7?
        public var startAt: Date
        /// Explicit end (due) time, e.g. from the capture sheet or a
        /// natural-language date. `nil` → derived from `startAt` via the
        /// work calendar's default end-of-business rule.
        public var endAt: Date?
        public var priority: Priority
        public var recurrence: Recurrence?
        public var color: String?
        public var tags: [String]
        public var placement: Placement
        /// When the task was made. `nil` → `startAt`, which is the same moment
        /// unless the start was rounded or picked by hand.
        public var createdAt: Date?

        public init(
            kind: WorkItem.Kind = .task,
            title: String,
            descriptionMd: String = "",
            parentId: UUIDv7? = nil,
            startAt: Date = .now,
            endAt: Date? = nil,
            priority: Priority = .default,
            recurrence: Recurrence? = nil,
            color: String? = nil,
            tags: [String] = [],
            placement: Placement = .bottom,
            createdAt: Date? = nil
        ) {
            self.kind = kind
            self.title = title
            self.descriptionMd = descriptionMd
            self.parentId = parentId
            self.startAt = startAt
            self.endAt = endAt
            self.priority = priority
            self.recurrence = recurrence
            self.color = color
            self.tags = tags
            self.placement = placement
            self.createdAt = createdAt
        }
    }

    public enum Error: Swift.Error, Equatable {
        case emptyTitle
        case titleTooLong
        case invalidParent(kind: WorkItem.Kind, parentKind: WorkItem.Kind?)
    }

    private let repository: any WorkItemRepository
    private let calendar: WorkCalendar
    private let deviceId: String

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar,
        deviceId: String = "local"
    ) {
        self.repository = repository
        self.calendar = calendar
        self.deviceId = deviceId
    }

    @discardableResult
    public func execute(_ input: Input) async throws -> WorkItem {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw Error.emptyTitle }
        guard title.count <= 200 else { throw Error.titleTooLong }

        if let parentId = input.parentId {
            guard let parent = await repository.item(parentId) else {
                throw Error.invalidParent(kind: input.kind, parentKind: nil)
            }
            guard input.kind.allowedParentKinds.contains(parent.kind) else {
                throw Error.invalidParent(kind: input.kind, parentKind: parent.kind)
            }
        }

        let endAt = TaskSchedule.dueAfterStart(
            start: input.startAt,
            due: input.endAt ?? calendar.defaultEndAt(createdAt: input.startAt)
        )
        let createdAt = input.createdAt ?? input.startAt
        let siblings = await repository.children(of: input.parentId)
        let displayOrder: String
        switch input.placement {
        case .top:
            displayOrder = FractionalIndex.midpoint(nil, siblings.first?.displayOrder)
        case .bottom:
            displayOrder = FractionalIndex.midpoint(siblings.last?.displayOrder, nil)
        }

        let item = WorkItem(
            kind: input.kind,
            title: title,
            parentId: input.parentId,
            descriptionMd: input.descriptionMd,
            priority: input.priority,
            recurrence: input.recurrence,
            startAt: input.startAt,
            endAt: endAt,
            displayOrder: displayOrder,
            color: input.color,
            tags: input.tags,
            createdAt: createdAt,
            updatedAt: createdAt,
            deviceId: deviceId
        )
        try await repository.save(item)
        return item
    }
}
