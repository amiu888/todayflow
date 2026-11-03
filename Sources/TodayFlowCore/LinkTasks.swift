import Foundation

/// Creates a link between two work items (driver.md §11 FR-30).
///
/// `.blocks` links form a one-way linked list: each item has at most one direct
/// predecessor and one direct successor, and cycles are rejected ("This would create a
/// loop", driver.md §11). `.relatesTo` links are informational and carry no such shape.
public struct LinkTasks: Sendable {
    public enum Error: Swift.Error, Equatable {
        case selfLink
        case notFound
        case duplicate
        case chainFull
        case wouldCreateLoop
    }

    private let linkRepository: any LinkRepository
    private let itemRepository: any WorkItemRepository
    private let deviceId: String

    public init(
        linkRepository: any LinkRepository,
        itemRepository: any WorkItemRepository,
        deviceId: String = "local"
    ) {
        self.linkRepository = linkRepository
        self.itemRepository = itemRepository
        self.deviceId = deviceId
    }

    @discardableResult
    public func execute(
        from: UUIDv7,
        to: UUIDv7,
        kind: ItemLink.Kind = .blocks,
        at: Date = .now
    ) async throws -> ItemLink {
        guard from != to else { throw Error.selfLink }
        guard await itemRepository.item(from) != nil,
              await itemRepository.item(to) != nil
        else { throw Error.notFound }

        let existing = await linkRepository.allLinks()
        if existing.contains(where: { $0.fromId == from && $0.toId == to && $0.kind == kind }) {
            throw Error.duplicate
        }

        if kind == .blocks {
            // Linked-list shape: an item has at most one outgoing and one incoming link.
            if existing.contains(where: { $0.kind == .blocks && $0.fromId == from && $0.toId != to }) {
                throw Error.chainFull
            }
            if existing.contains(where: { $0.kind == .blocks && $0.toId == to && $0.fromId != from }) {
                throw Error.chainFull
            }
            // Cycle: adding from → to loops if `to` already reaches `from`.
            if reaches(from: to, to: from, in: existing) {
                throw Error.wouldCreateLoop
            }
        }

        let link = ItemLink(fromId: from, toId: to, kind: kind, createdAt: at, deviceId: deviceId)
        try await linkRepository.save(link)
        return link
    }

    /// True if `start` can reach `target` by following `.blocks` links (transitively).
    private func reaches(from start: UUIDv7, to target: UUIDv7, in links: [ItemLink]) -> Bool {
        var frontier = [start]
        var visited: Set<UUIDv7> = [start]
        while let current = frontier.popLast() {
            if current == target { return true }
            for link in links where link.kind == .blocks && link.fromId == current {
                if visited.insert(link.toId).inserted {
                    frontier.append(link.toId)
                }
            }
        }
        return false
    }
}
