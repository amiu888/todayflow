import Foundation

/// Changes an item's position within its parent's list (driver.md §11 FR-12).
///
/// Computes a new fractional-index key between the given neighbors and persists it, so
/// a reorder is a single in-place update (no reindex of siblings). Moving the item to a
/// new parent (drag-to-reparent) is also supported and validated against the hierarchy.
public struct ReorderTask: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case invalidParent(kind: WorkItem.Kind, parentKind: WorkItem.Kind?)
    }

    private let repository: any WorkItemRepository
    private let deviceId: String

    public init(repository: any WorkItemRepository, deviceId: String = "local") {
        self.repository = repository
        self.deviceId = deviceId
    }

    /// Move `id` to sit between `beforeId` (upper bound) and `afterId` (lower bound) —
    /// either may be `nil` for a list end — and, if `newParentId` is given, reparent it.
    ///
    /// - `toTopLevel` moves the item to the top-level list (parent `nil`), overriding
    ///   `newParentId`. Every kind may stand alone, so no kind validation is needed.
    /// - `newDisplayOrder` sets an explicit fractional-index key, skipping the neighbor
    ///   midpoint computation. The Today list reorders a flat, cross-parent sequence,
    ///   so it computes the key itself (from the visible rows' keys) and passes it here;
    ///   the item keeps its current parent unless `toTopLevel` is set.
    @discardableResult
    public func execute(
        _ id: UUIDv7,
        beforeId: UUIDv7? = nil,
        afterId: UUIDv7? = nil,
        newParentId: UUIDv7? = nil,
        toTopLevel: Bool = false,
        newDisplayOrder: String? = nil,
        at: Date = .now
    ) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }

        let newParent: UUIDv7?
        if toTopLevel {
            newParent = nil
        } else if let newParentId {
            guard let parent = await repository.item(newParentId) else {
                throw Error.invalidParent(kind: item.kind, parentKind: nil)
            }
            guard item.kind.allowedParentKinds.contains(parent.kind) else {
                throw Error.invalidParent(kind: item.kind, parentKind: parent.kind)
            }
            newParent = newParentId
        } else {
            newParent = item.parentId
        }

        let siblings = await repository.children(of: newParent)
        let displayOrder: String
        if let newDisplayOrder {
            displayOrder = newDisplayOrder
        } else {
            let beforeKey = beforeId.flatMap { bid in siblings.first { $0.id == bid }?.displayOrder }
            let afterKey = afterId.flatMap { aid in siblings.first { $0.id == aid }?.displayOrder }
            displayOrder = FractionalIndex.midpoint(afterKey, beforeKey)
        }

        item.parentId = newParent
        item.displayOrder = displayOrder
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.move(id, toParent: newParent, displayOrder: displayOrder, at: at)
        return item
    }
}
