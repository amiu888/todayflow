import Foundation

/// Creates a work item with the app's default dates and ordering (driver.md §11).
///
/// - `endAt` defaults to the `WorkCalendar` end-of-business for the start day
///   (dropped 10:42 on a weekday → 17:00 today; dropped 18:30 → next business day 17:00).
/// - `displayOrder` is appended after the last existing sibling.
/// - The hierarchy is validated against `WorkItem.Kind.allowedParentKinds`.
public struct CreateTask: Sendable {
    public struct Input {
        public var kind: WorkItem.Kind
        public var title: String
        public var descriptionMd: String
        public var parentId: UUIDv7?
        public var startAt: Date
        public var priority: Priority
        public var color: String?
        public var tags: [String]

        public init(
            kind: WorkItem.Kind = .task,
            title: String,
            descriptionMd: String = "",
            parentId: UUIDv7? = nil,
            startAt: Date = .now,
            priority: Priority = .default,
            color: String? = nil,
            tags: [String] = []
        ) {
            self.kind = kind
            self.title = title
            self.descriptionMd = descriptionMd
            self.parentId = parentId
            self.startAt = startAt
            self.priority = priority
            self.color = color
            self.tags = tags
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

        let endAt = calendar.defaultEndAt(createdAt: input.startAt)
        let siblings = await repository.children(of: input.parentId)
        let displayOrder = FractionalIndex.midpoint(siblings.last?.displayOrder, nil)

        let item = WorkItem(
            kind: input.kind,
            title: title,
            parentId: input.parentId,
            descriptionMd: input.descriptionMd,
            priority: input.priority,
            startAt: input.startAt,
            endAt: endAt,
            displayOrder: displayOrder,
            color: input.color,
            tags: input.tags,
            createdAt: input.startAt,
            updatedAt: input.startAt,
            deviceId: deviceId
        )
        try await repository.save(item)
        return item
    }
}
