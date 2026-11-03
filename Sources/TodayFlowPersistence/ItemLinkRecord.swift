import Foundation
import GRDB
import TodayFlowCore

extension ItemLink.Kind {
    /// The snake_case value stored in the `item_link.type` column.
    var dbValue: String {
        switch self {
        case .blocks: return "blocks"
        case .relatesTo: return "relates_to"
        }
    }

    init(dbValue: String) {
        switch dbValue {
        case "relates_to": self = .relatesTo
        default: self = .blocks
        }
    }
}

/// Maps an `item_link` row to the Core `ItemLink` model.
///
/// The `item_link` table has no `device_id` column (driver.md §6), so the model's
/// `deviceId` reads back as `"local"`.
struct ItemLinkRecord {
    var model: ItemLink

    init(row: Row) {
        model = ItemLink(
            id: UUIDv7(databaseString: row["id"] as String),
            fromId: UUIDv7(databaseString: row["from_id"] as String),
            toId: UUIDv7(databaseString: row["to_id"] as String),
            kind: ItemLink.Kind(dbValue: row["type"] as String),
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            version: row["version"] as Int,
            deviceId: "local"
        )
    }
}
