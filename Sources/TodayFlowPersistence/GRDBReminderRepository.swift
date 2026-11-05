import Foundation
import GRDB
import TodayFlowCore

/// GRDB adapter for per-task reminders (FR-42). Uses the `reminder` table
/// already present in schema v1.
public final class GRDBReminderRepository: ReminderRepository, Sendable {
    private let queue: DatabaseQueue
    private let actor: String

    public init(queue: DatabaseQueue, actor: String = ActivityActor.current) {
        self.queue = queue
        self.actor = actor
    }

    public func reminder(for itemId: UUIDv7, kind: Reminder.Kind) async -> Reminder? {
        let reminder = try? await queue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM reminder
                    WHERE work_item_id = ? AND kind = ? AND deleted_at IS NULL
                    ORDER BY fire_at
                    LIMIT 1
                    """,
                arguments: [itemId.uuid.uuidString, kind.dbValue]
            ).map { ReminderRecord(row: $0).model }
        }
        return reminder ?? nil
    }

    public func save(_ reminder: Reminder) async throws {
        let actor = self.actor
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO reminder (
                      id, work_item_id, fire_at, kind, delivered_at,
                      created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(id) DO UPDATE SET
                      work_item_id = excluded.work_item_id,
                      fire_at = excluded.fire_at,
                      kind = excluded.kind,
                      delivered_at = excluded.delivered_at,
                      updated_at = excluded.updated_at,
                      deleted_at = NULL
                    """,
                arguments: [
                    reminder.id.uuid.uuidString,
                    reminder.itemId?.uuid.uuidString,
                    SqlTimestamp.encode(reminder.fireAt),
                    reminder.kind.dbValue,
                    reminder.deliveredAt.map(SqlTimestamp.encode),
                    SqlTimestamp.encode(reminder.createdAt),
                    SqlTimestamp.encode(reminder.createdAt),
                ]
            )

            if let itemId = reminder.itemId {
                try ActivityLog.append(
                    db,
                    ActivityEvent(
                        itemId: itemId,
                        kind: .reminderSet,
                        summary: "Reminder set for \(reminder.fireAt.formatted(date: .abbreviated, time: .shortened))",
                        actor: actor,
                        occurredAt: reminder.createdAt,
                        metadata: [
                            "reminder_id": reminder.id.uuid.uuidString,
                            "fire_at": ISO8601DateFormatter().string(from: reminder.fireAt),
                        ],
                        deviceId: reminder.deviceId
                    )
                )
            }
        }
    }

    public func delete(_ id: UUIDv7) async throws {
        let actor = self.actor
        try await queue.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM reminder WHERE id = ?",
                arguments: [id.uuid.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM reminder WHERE id = ?",
                arguments: [id.uuid.uuidString]
            )
            if let row {
                let reminder = ReminderRecord(row: row).model
                if let itemId = reminder.itemId {
                    try ActivityLog.append(
                        db,
                        ActivityEvent(
                            itemId: itemId,
                            kind: .reminderCleared,
                            summary: "Reminder cleared",
                            actor: actor,
                            occurredAt: .now,
                            metadata: ["reminder_id": reminder.id.uuid.uuidString],
                            deviceId: reminder.deviceId
                        )
                    )
                }
            }
        }
    }

    public func pending(after date: Date) async -> [Reminder] {
        let reminders = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM reminder
                    WHERE deleted_at IS NULL
                      AND delivered_at IS NULL
                      AND fire_at > ?
                    ORDER BY fire_at
                    """,
                arguments: [SqlTimestamp.encode(date)]
            ).map { ReminderRecord(row: $0).model }
        }
        return reminders ?? []
    }
}
