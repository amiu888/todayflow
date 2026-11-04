import Foundation

/// Changes a work item's priority (driver.md §4 row quick action).
public struct SetPriority: Sendable {
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
        to priority: Priority,
        at: Date = .now
    ) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }
        guard item.priority != priority else { throw Error.unchanged }

        item.priority = priority
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
