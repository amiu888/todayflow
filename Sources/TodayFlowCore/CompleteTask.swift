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

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        deriver: StatusDeriver = StatusDeriver(),
        deviceId: String = "local"
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.deriver = deriver
        self.deviceId = deviceId
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

        item.status = .done
        item.completedAt = at
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
