import Foundation

/// Moves a task's due time to the next working day's end of business
/// (driver.md §4 row quick action, FR-42/FR-43 "Move to tomorrow").
///
/// "Tomorrow" means the next *working* day, so a Friday move lands on Monday's
/// EOB. The item's `startAt` is untouched — only the due time shifts.
public struct MoveToTomorrow: Sendable {
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

    /// The end-of-business instant of the first working day strictly after
    /// `day`'s calendar day.
    public func nextWorkingDayEOB(after day: Date) -> Date {
        var current = calendar.calendar.startOfDay(for: day)
        while true {
            let next = calendar.calendar.date(byAdding: .day, value: 1, to: current) ?? current
            if calendar.isWorkingDay(next) {
                return calendar.endOfBusiness(for: next)
            }
            current = next
        }
    }

    @discardableResult
    public func execute(_ id: UUIDv7, at: Date = .now) async throws -> WorkItem {
        guard var item = await repository.item(id) else { throw Error.notFound }
        item.endAt = nextWorkingDayEOB(after: at)
        item = item.touching(at)
        item.deviceId = deviceId
        try await repository.save(item)
        return item
    }
}
