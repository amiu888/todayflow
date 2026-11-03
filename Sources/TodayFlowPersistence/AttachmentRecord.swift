import Foundation
import GRDB
import TodayFlowCore

extension Attachment.Kind {
    /// The snake_case value stored in the `attachment.type` column.
    var dbValue: String {
        switch self {
        case .file: return "file"
        case .folder: return "folder"
        case .email: return "email"
        case .calendarEvent: return "calendar_event"
        case .teamsMessage: return "teams_message"
        case .url: return "url"
        case .image: return "image"
        case .text: return "text"
        }
    }

    init(dbValue: String) {
        switch dbValue {
        case "calendar_event": self = .calendarEvent
        case "teams_message": self = .teamsMessage
        default: self = Attachment.Kind(rawValue: dbValue) ?? .text
        }
    }
}

/// Maps an `attachment` row to the Core `Attachment` model.
///
/// - `reference` is `NOT NULL` in the schema but optional in the model: an empty
///   string reads back as `nil`.
/// - The table has no `device_id` column; the model reads back `"local"`.
struct AttachmentRecord {
    var model: Attachment

    init(row: Row) {
        let reference = row["reference"] as String
        model = Attachment(
            id: UUIDv7(databaseString: row["id"] as String),
            itemId: UUIDv7(databaseString: row["work_item_id"] as String),
            kind: Attachment.Kind(dbValue: row["type"] as String),
            uti: row["uti"] as String?,
            displayName: row["display_name"] as String,
            sourceApp: row["source_app"] as String?,
            reference: reference.isEmpty ? nil : reference,
            bookmark: row["bookmark"] as Data?,
            localCopyPath: row["local_copy_path"] as String?,
            metadata: Json.object(from: row["metadata_json"] as String),
            previewText: row["preview_text"] as String?,
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            version: row["version"] as Int,
            deviceId: "local"
        )
    }
}
