import Foundation
import GRDB
import TodayFlowCore

/// Maps an `activity` row to the Core `ActivityEvent` model.
struct ActivityRecord {
    var event: ActivityEvent

    init(row: Row) {
        event = ActivityEvent(
            id: UUIDv7(databaseString: row["id"] as String),
            itemId: UUIDv7(databaseString: row["work_item_id"] as String),
            kind: ActivityEvent.Kind(rawValue: row["kind"] as String) ?? .other,
            summary: row["summary"] as String,
            actor: row["actor"] as String,
            sourceApp: row["source_app"] as String?,
            location: row["location"] as String?,
            occurredAt: SqlTimestamp.decode(row["occurred_at"] as String) ?? .distantPast,
            metadata: Json.object(from: row["metadata_json"] as String),
            deviceId: row["device_id"] as String
        )
    }
}

/// One place that writes activity rows, so every adapter uses the same SQL.
enum ActivityLog {
    static func title(_ db: Database, for id: UUIDv7) throws -> String {
        try String.fetchOne(
            db,
            sql: "SELECT title FROM work_item WHERE id = ?",
            arguments: [id.uuid.uuidString]
        ) ?? "task"
    }

    static func append(_ db: Database, _ event: ActivityEvent) throws {
        try db.execute(
            sql: """
                INSERT INTO activity (
                  id, work_item_id, kind, summary, actor, source_app, location,
                  occurred_at, metadata_json, device_id
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                event.id.uuid.uuidString,
                event.itemId.uuid.uuidString,
                event.kind.rawValue,
                event.summary,
                event.actor,
                event.sourceApp,
                event.location,
                SqlTimestamp.encode(event.occurredAt),
                Json.objectString(event.metadata),
                event.deviceId,
            ]
        )
    }
}
