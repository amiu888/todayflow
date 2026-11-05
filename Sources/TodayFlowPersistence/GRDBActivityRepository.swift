import Foundation
import GRDB
import TodayFlowCore

/// GRDB adapter for the append-only activity log (FR-20).
public final class GRDBActivityRepository: ActivityRepository, Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public func record(_ event: ActivityEvent) async throws {
        try await queue.write { db in
            try ActivityLog.append(db, event)
        }
    }

    public func events(for itemId: UUIDv7) async -> [ActivityEvent] {
        let events = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM activity
                    WHERE work_item_id = ?
                    ORDER BY occurred_at DESC, id DESC
                    """,
                arguments: [itemId.uuid.uuidString]
            ).map { ActivityRecord(row: $0).event }
        }
        return events ?? []
    }

    public func recent(limit: Int) async -> [ActivityEvent] {
        let events = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM activity
                    ORDER BY occurred_at DESC, id DESC
                    LIMIT ?
                    """,
                arguments: [max(0, limit)]
            ).map { ActivityRecord(row: $0).event }
        }
        return events ?? []
    }
}
