import Foundation

/// Marks a work item done (driver.md §11 FR-14, FR-31).
///
/// A blocked item (an unresolved prerequisite) cannot be completed unless `force` is
/// set — the "override with a confirmation" path (driver.md §2). Because `blocked` is
/// derived rather than stored, completing a prerequisite needs **no** write to its
/// dependents: they simply re-derive to unblocked on the next read.
public struct CompleteTask: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case blocked
        case alreadyTerminal
    }

    private let repository: any WorkItemRepository
    private let linkRepository: any LinkRepository
    private let deriver: StatusDeriver
    private let deviceId: String
    private let calendar: Calendar

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        deriver: StatusDeriver = StatusDeriver(),
        deviceId: String = "local",
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.deriver = deriver
        self.deviceId = deviceId
        self.calendar = calendar
    }

    /// The item's direct prerequisites (the `from` end of `.blocks` links pointing at it).
    private func prerequisites(of id: UUIDv7) async -> [WorkItem] {
        let links = await linkRepository.links(to: id).filter { $0.kind == .blocks }
        var result: [WorkItem] = []
        for link in links {
            if let from = await repository.item(link.fromId) {
                result.append(from)
            }
        }
        return result
    }

    @discardableResult
    public func execute(_ id: UUIDv7, at: Date = .now, force: Bool = false) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }
        guard !item.status.isTerminal else { throw Error.alreadyTerminal }

        let blockers = await prerequisites(of: id)
        if deriver.derive(stored: item.status, blockers: blockers) == .blocked, !force {
            throw Error.blocked
        }

        let recurrence = item.recurrence
        item.status = .done
        item.completedAt = at
        // The completed occurrence is the history entry; the next occurrence
        // carries the rule so reopening this one cannot spawn duplicates.
        item.recurrence = nil
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.save(item)

        if let recurrence,
           let next = nextOccurrence(
               for: item,
               rule: recurrence,
               completedAt: at
           )
        {
            let siblings = await repository.children(of: item.parentId)
            let nextItem = WorkItem(
                kind: item.kind,
                title: item.title,
                parentId: item.parentId,
                descriptionMd: item.descriptionMd,
                summary: item.summary,
                status: .todo,
                priority: item.priority,
                recurrence: recurrence,
                startAt: next.start,
                endAt: next.end,
                estimatedMinutes: item.estimatedMinutes,
                displayOrder: FractionalIndex.midpoint(
                    siblings.last?.displayOrder,
                    nil
                ),
                color: item.color,
                tags: item.tags,
                createdAt: at,
                updatedAt: at,
                deviceId: deviceId
            )
            try await repository.save(nextItem)
        }
        return item
    }

    /// The next future occurrence, preserving the task's duration. Completing
    /// a task late skips occurrences that are already in the past.
    private func nextOccurrence(
        for item: WorkItem,
        rule: Recurrence,
        completedAt: Date
    ) -> (start: Date, end: Date)? {
        guard var start = rule.nextStart(after: item.startAt, calendar: calendar) else {
            return nil
        }
        var attempts = 0
        while start <= completedAt, attempts < 10_000 {
            guard let following = rule.nextStart(after: start, calendar: calendar) else {
                return nil
            }
            start = following
            attempts += 1
        }
        let duration = max(0, item.endAt.timeIntervalSince(item.startAt))
        return (start, start.addingTimeInterval(duration))
    }
}
