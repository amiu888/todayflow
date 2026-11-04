import Foundation

/// Deletes a work item, reconnecting any dependency chain it sat in the middle of
/// (driver.md §11 FR-32: "Removing a task from the middle of a chain reconnects its
/// predecessor to its successor").
///
/// Soft-deletes the item and merges the `.blocks` chain: for each predecessor →
/// item → successor, a direct predecessor → successor link is created, then every
/// link touching the item is removed.
///
/// Children are **never deleted by default** (driver.md §2: "Deleting a parent
/// never deletes children by default; children become unparented") — after the
/// soft-delete, each direct child is re-parented to the top level. Passing
/// `withChildren: true` takes the explicit "delete with children" option: every
/// descendant is soft-deleted along with the item, and their links are removed.
public struct DeleteTask: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
    }

    private let itemRepository: any WorkItemRepository
    private let linkRepository: any LinkRepository
    private let deviceId: String

    public init(
        itemRepository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        deviceId: String = "local"
    ) {
        self.itemRepository = itemRepository
        self.linkRepository = linkRepository
        self.deviceId = deviceId
    }

    @discardableResult
    public func execute(
        _ id: UUIDv7,
        withChildren: Bool = false,
        at: Date = .now
    ) async throws -> WorkItem {
        guard let item = await itemRepository.item(id) else { throw Error.notFound }

        let allLinks = await linkRepository.allLinks()
        let predecessors = allLinks.filter { $0.kind == .blocks && $0.toId == id }
        let successors = allLinks.filter { $0.kind == .blocks && $0.fromId == id }

        // Reconnect each predecessor directly to each successor (linked-list: ≤ 1 each).
        for pre in predecessors {
            for succ in successors {
                let merged = ItemLink(fromId: pre.fromId, toId: succ.toId, kind: .blocks, createdAt: at, deviceId: deviceId)
                try await linkRepository.save(merged)
            }
        }

        // The explicit "delete with children" option (driver.md §2): every
        // descendant is soft-deleted with the item, links and all.
        let doomed: Set<UUIDv7> = withChildren
            ? await allDescendantIds(of: id)
            : []
        for link in allLinks where link.fromId == id || link.toId == id
            || doomed.contains(link.fromId) || doomed.contains(link.toId) {
            try await linkRepository.delete(link.id)
        }
        for descendantId in doomed {
            try await itemRepository.softDelete(descendantId, at: at)
        }

        try await itemRepository.softDelete(id, at: at)

        // The default: children survive, unparented (driver.md §2).
        if !withChildren {
            for var child in await itemRepository.children(of: id) {
                child.parentId = nil
                child = child.touching(at)
                try await itemRepository.save(child)
            }
        }
        return item
    }

    /// Every live descendant of `id` (direct children, their children, …) via
    /// breadth-first traversal.
    private func allDescendantIds(of id: UUIDv7) async -> Set<UUIDv7> {
        var found = Set<UUIDv7>()
        var frontier = [id]
        while let current = frontier.popLast() {
            for child in await itemRepository.children(of: current) {
                guard found.insert(child.id).inserted else { continue }
                frontier.append(child.id)
            }
        }
        return found
    }
}
