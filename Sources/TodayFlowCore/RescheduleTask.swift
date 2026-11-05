import Foundation

/// Moves a task's due time to the end of business on a chosen day
/// (driver.md FR-43: "Pick a date" in the end-of-day review).
///
/// Only the due time changes: `startAt` stays where it was unless it would
/// otherwise fall after the new due time (for example moving an old overdue
/// task to tomorrow). A date whose end of business is already in the past is
/// rejected so a review can never make a task permanently overdue again.
public struct RescheduleTask: Sendable {
    public enum Error: Swift.Error, Equatable {
        case notFound
        case dateInPast
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

    /// The end-of-business instant on `day`.
    public func endOfBusiness(on day: Date) -> Date {
        calendar.endOfBusiness(for: day)
    }

    @discardableResult
    public func execute(
        _ id: UUIDv7,
        to day: Date,
        at now: Date = .now
    ) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }

        let endAt = calendar.endOfBusiness(for: day)
        guard endAt > now else { throw Error.dateInPast }

        item.endAt = endAt
        if item.startAt > endAt {
            item.startAt = calendar.startOfBusiness(for: day)
        }
        item = item.touching(now)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
