import Foundation

/// In-memory `ActivityRepository` for tests, previews, and the app's test
/// environment. Production uses `GRDBActivityRepository`.
public actor InMemoryActivityRepository: ActivityRepository {
    private var events: [ActivityEvent] = []

    public init() {}

    public func record(_ event: ActivityEvent) async throws {
        events.append(event)
    }

    public func events(for itemId: UUIDv7) async -> [ActivityEvent] {
        events
            .filter { $0.itemId == itemId }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    public func recent(limit: Int) async -> [ActivityEvent] {
        Array(events.sorted { $0.occurredAt > $1.occurredAt }.prefix(max(0, limit)))
    }

    // MARK: Test helpers

    public func seed(_ event: ActivityEvent) {
        events.append(event)
    }

    public var all: [ActivityEvent] {
        events.sorted { $0.occurredAt > $1.occurredAt }
    }
}
