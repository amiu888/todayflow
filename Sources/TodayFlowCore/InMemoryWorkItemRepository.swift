import Foundation

/// In-memory `WorkItemRepository` (driver.md §5: every port has an in-memory adapter).
///
/// An actor so it is safe to share across concurrency domains in tests and previews.
/// Serves the same port the GRDB production adapter (TodayFlowPersistence) will.
public actor InMemoryWorkItemRepository: WorkItemRepository {
    private struct Observer {
        let day: Date
        let calendar: WorkCalendar
        let continuation: AsyncStream<[WorkItem]>.Continuation
    }

    private var items: [UUIDv7: WorkItem] = [:]
    private var observers: [UUID: Observer] = [:]

    public init() {}

    // MARK: WorkItemRepository

    public func item(_ id: UUIDv7) async -> WorkItem? {
        guard let item = items[id], !item.isDeleted else { return nil }
        return item
    }

    public func todayItems(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        let eob = calendar.endOfBusiness(for: day)
        return items.values
            .filter { !$0.isDeleted && !$0.status.isTerminal && $0.startAt <= eob }
            .sorted { FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder) }
    }

    public func completedToday(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        let cal = calendar.calendar
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return items.values
            .filter {
                guard !$0.isDeleted, $0.status == .done else { return false }
                let when = $0.completedAt ?? $0.updatedAt
                return when >= dayStart && when < dayEnd
            }
            .sorted { FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder) }
    }

    public func children(of parentId: UUIDv7?) async -> [WorkItem] {
        items.values
            .filter { !$0.isDeleted && $0.parentId == parentId }
            .sorted { FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder) }
    }

    public func save(_ item: WorkItem) async throws {
        items[item.id] = item
        await notifyObservers()
    }

    public func softDelete(_ id: UUIDv7, at: Date) async throws {
        guard var item = items[id] else { return }
        item.deletedAt = at
        item = item.touching(at)
        items[id] = item
        await notifyObservers()
    }

    public func move(_ id: UUIDv7, toParent: UUIDv7?, displayOrder: String, at: Date) async throws {
        guard var item = items[id] else { return }
        item.parentId = toParent
        item.displayOrder = displayOrder
        item = item.touching(at)
        items[id] = item
        await notifyObservers()
    }

    public func observeToday(on day: Date, calendar: WorkCalendar) async -> AsyncStream<[WorkItem]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: [WorkItem].self)
        observers[id] = Observer(day: day, calendar: calendar, continuation: continuation)
        continuation.yield(await todayItems(on: day, calendar: calendar))
        continuation.onTermination = { @Sendable _ in
            Task { await self.removeObserver(id) }
        }
        return stream
    }

    public func search(_ query: String) async -> [WorkItem] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        return items.values
            .filter {
                !$0.isDeleted &&
                ($0.title.lowercased().contains(needle)
                    || $0.descriptionMd.lowercased().contains(needle))
            }
            .sorted { FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder) }
    }

    // MARK: Observer bookkeeping

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notifyObservers() async {
        for observer in observers.values {
            observer.continuation.yield(await todayItems(on: observer.day, calendar: observer.calendar))
        }
    }

    // MARK: Test helpers

    /// All items, including soft-deleted ones.
    public var allItems: [WorkItem] { Array(items.values) }

    /// Insert without notifying observers (for seeding fixtures).
    public func seed(_ item: WorkItem) {
        items[item.id] = item
    }
}
