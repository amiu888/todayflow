import Foundation

/// Persistence for the checkable action list inside a work item.
public protocol ActionItemRepository: Sendable {
    /// Live actions for one item, ordered for display.
    func actions(for itemId: UUIDv7) async -> [ActionItem]
    /// Insert or update an action.
    func save(_ action: ActionItem) async throws
    /// Remove an action from the list.
    func delete(_ id: UUIDv7) async throws
}

/// In-memory actions for tests and previews.
public actor InMemoryActionItemRepository: ActionItemRepository {
    private var items: [UUIDv7: ActionItem] = [:]

    public init() {}

    public func actions(for itemId: UUIDv7) async -> [ActionItem] {
        items.values
            .filter { $0.itemId == itemId }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.createdAt < $1.createdAt
            }
    }

    public func save(_ action: ActionItem) async throws {
        items[action.id] = action
    }

    public func delete(_ id: UUIDv7) async throws {
        items.removeValue(forKey: id)
    }

    // MARK: Test helpers

    public func seed(_ action: ActionItem) {
        items[action.id] = action
    }

    public var all: [ActionItem] { Array(items.values) }
}
