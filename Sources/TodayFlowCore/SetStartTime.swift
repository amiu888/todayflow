import Foundation

/// Moves a task's start time while keeping a valid due time (FR-22/FR-43).
///
/// If the new start would fall after the current due time, the due time is
/// recomputed with the work calendar's default rule (today's EOB, or the next
/// business day after hours).
public struct SetStartTime: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
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
    public func execute(
        _ id: UUIDv7,
        to startAt: Date,
        at now: Date = .now
    ) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }

        item.startAt = startAt
        if item.endAt <= startAt {
            item.endAt = calendar.defaultEndAt(createdAt: startAt)
        }
        item = item.touching(now)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
