import Foundation
import GRDB
import TodayFlowCore

extension Reminder.Kind {
    /// The snake_case value stored in the `reminder.kind` column.
    var dbValue: String {
        switch self {
        case .task: return "task"
        case .endOfDay: return "end_of_day"
        }
    }

    init(dbValue: String) {
        switch dbValue {
        case "end_of_day": self = .endOfDay
        default: self = .task
        }
    }
}

/// Maps a `reminder` row to the Core `Reminder` model.
///
/// The `reminder` table has no `version` or `device_id` column (driver.md §6);
/// the model's `version` uses its default of 1 and `deviceId` reads back as
/// `"local"`.
struct ReminderRecord {
    var model: Reminder

    init(row: Row) {
        model = Reminder(
            id: UUIDv7(databaseString: row["id"] as String),
            itemId: (row["work_item_id"] as String?).map { UUIDv7(databaseString: $0) },
            kind: Reminder.Kind(dbValue: row["kind"] as String),
            fireAt: SqlTimestamp.decode(row["fire_at"] as String) ?? .distantPast,
            deliveredAt: (row["delivered_at"] as String?).flatMap(SqlTimestamp.decode),
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            deviceId: "local"
        )
    }
}
