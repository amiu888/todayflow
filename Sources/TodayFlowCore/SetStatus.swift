import Foundation

/// Sets a work item's status (driver.md §2 status lifecycle).
///
/// Owns the `completedAt` stamp: moving to `.done` records the completion time,
/// leaving `.done` clears it. Serves the complete-undo path (FR-14: done → the
/// previous status) and the detail view's status picker (increment 5c).
public struct SetStatus: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case unchanged
    }

    private let repository: any WorkItemRepository
    private let deviceId: String

    public init(
        repository: any WorkItemRepository,
        deviceId: String = "local"
    ) {
        self.repository = repository
        self.deviceId = deviceId
    }

    @discardableResult
    public func execute(
        _ id: UUIDv7,
        to newStatus: Status,
        at: Date = .now
    ) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }
        guard item.status != newStatus else { throw Error.unchanged }

        item.status = newStatus
        item.completedAt = newStatus == .done ? at : nil
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
