import Foundation
import GRDB
import TodayFlowCore

struct ContactRecord {
    var model: Contact

    init(row: Row) {
        model = Contact(
            id: UUIDv7(databaseString: row["id"] as String),
            firstName: row["first_name"] as String,
            lastName: row["last_name"] as String,
            company: row["company"] as String,
            jobTitle: row["job_title"] as String,
            emails: Json.array(from: row["emails_json"] as String),
            phones: Json.array(from: row["phones_json"] as String),
            notes: row["notes"] as String,
            source: row["source"] as String,
            externalId: row["external_id"] as String?,
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            updatedAt: SqlTimestamp.decode(row["updated_at"] as String) ?? .distantPast,
            deletedAt: (row["deleted_at"] as String?).flatMap(SqlTimestamp.decode),
            version: row["version"] as Int,
            deviceId: row["device_id"] as String
        )
    }
}

struct ContactGroupRecord {
    var model: ContactGroup

    init(row: Row) {
        model = ContactGroup(
            id: UUIDv7(databaseString: row["id"] as String),
            name: row["name"] as String,
            colorHex: row["color_hex"] as String,
            sortOrder: row["sort_order"] as String,
            createdAt: SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast,
            updatedAt: SqlTimestamp.decode(row["updated_at"] as String) ?? .distantPast,
            version: row["version"] as Int,
            deviceId: row["device_id"] as String
        )
    }
}
