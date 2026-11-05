import Foundation
import GRDB
import TodayFlowCore

/// Maps a `work_item` row to the Core `WorkItem` model.
///
/// Column ↔ model notes:
/// - `kind` / `status` / `priority` fall back to safe defaults if the stored
///   string is not a known value (defensive: the columns are CHECK-constrained,
///   but a hand-edited database should degrade, not trap).
/// - `start_at` / `end_at` are nullable in the schema; the model is not, so
///   `nil` decodes to `.distantPast`.
/// - `device_id` is the only table with a device column (driver.md §6).
struct WorkItemRecord {
    var model: WorkItem

    init(row: Row) {
        model = WorkItem(
            id: UUIDv7(databaseString: row["id"] as String),
            kind: WorkItem.Kind(rawValue: row["kind"] as String) ?? .task,
            title: row["title"] as String,
            parentId: (row["parent_id"] as String?).map { UUIDv7(databaseString: $0) },
            descriptionMd: row["description_md"] as String,
            status: Status(rawValue: row["status"] as String) ?? .todo,
            priority: Priority(rawValue: row["priority"] as Int) ?? .normal,
            startAt: (row["start_at"] as String?).flatMap(SqlTimestamp.decode) ?? .distantPast,
            endAt: (row["end_at"] as String?).flatMap(SqlTimestamp.decode) ?? .distantPast,
            estimatedMinutes: row["estimated_minutes"] as Int?,
            completedAt: (row["completed_at"] as String?).flatMap(SqlTimestamp.decode),
            displayOrder: row["display_order"] as String,
            color: row["color"] as String?,
            tags: Json.array(from: row["tags_json"] as String),
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            updatedAt: SqlTimestamp.decode(row["updated_at"] as String) ?? .distantPast,
            deletedAt: (row["deleted_at"] as String?).flatMap(SqlTimestamp.decode),
            version: row["version"] as Int,
            deviceId: row["device_id"] as String
        )
    }
}
