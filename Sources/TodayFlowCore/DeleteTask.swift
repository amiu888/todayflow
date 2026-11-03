import Foundation

/// Deletes a work item, reconnecting any dependency chain it sat in the middle of
/// (driver.md §11 FR-32: "Removing a task from the middle of a chain reconnects its
/// predecessor to its successor").
///
/// Soft-deletes the item (its children are preserved, driver.md §2) and merges the
/// `.blocks` chain: for each predecessor → item → successor, a direct predecessor →
/// successor link is created, then every link touching the item is removed.
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
    public func execute(_ id: UUIDv7, at: Date = .now) async throws -> WorkItem {
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
        // Remove every link that touches the deleted item.
        for link in allLinks where link.fromId == id || link.toId == id {
            try await linkRepository.delete(link.id)
        }

        try await itemRepository.softDelete(id, at: at)
        return item
    }
}
