import Foundation
import GRDB
import TodayFlowCore

/// Maps an `action_item` row to the Core `ActionItem` model.
///
/// `sort_order` is a TEXT column in the schema (fractional-index style, like
/// `display_order`); the model's `Int` reads back via `Int(String)` with a
/// defensive `0` fallback. The table has no `device_id` column.
struct ActionItemRecord {
    var model: ActionItem

    init(row: Row) {
        model = ActionItem(
            id: UUIDv7(databaseString: row["id"] as String),
            itemId: UUIDv7(databaseString: row["work_item_id"] as String),
            text: row["text"] as String,
            isDone: row["is_done"] as Bool,
            sortOrder: Int(row["sort_order"] as String) ?? 0,
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            version: row["version"] as Int,
            deviceId: "local"
        )
    }
}
