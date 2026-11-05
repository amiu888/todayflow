import Foundation
import GRDB
import TodayFlowCore

/// GRDB-backed contacts, groups, and task links. Contacts are soft-deleted so
/// imports and future sync can reconcile without losing history.
public struct GRDBContactRepository: ContactRepository {
    private let queue: DatabaseQueue
    private let deviceId: String

    public init(queue: DatabaseQueue, deviceId: String = "local") {
        self.queue = queue
        self.deviceId = deviceId
    }

    public func contacts() async -> [Contact] {
        do {
            return try await queue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM contact
                        WHERE deleted_at IS NULL
                        ORDER BY last_name COLLATE NOCASE, first_name COLLATE NOCASE
                        """
                ).map { ContactRecord(row: $0).model }
            }
        } catch {
            return []
        }
    }

    public func contact(_ id: UUIDv7) async -> Contact? {
        try? await queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM contact WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.uuid.uuidString]
            ).map { ContactRecord(row: $0).model }
        }
    }

    public func save(_ contact: Contact) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO contact (
                      id, first_name, last_name, company, job_title,
                      emails_json, phones_json, notes, source, external_id,
                      created_at, updated_at, deleted_at, version, device_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      first_name = excluded.first_name,
                      last_name = excluded.last_name,
                      company = excluded.company,
                      job_title = excluded.job_title,
                      emails_json = excluded.emails_json,
                      phones_json = excluded.phones_json,
                      notes = excluded.notes,
                      source = excluded.source,
                      external_id = excluded.external_id,
                      updated_at = excluded.updated_at,
                      deleted_at = excluded.deleted_at,
                      version = excluded.version,
                      device_id = excluded.device_id
                    """,
                arguments: [
                    contact.id.uuid.uuidString,
                    contact.firstName,
                    contact.lastName,
                    contact.company,
                    contact.jobTitle,
                    Json.arrayString(contact.emails),
                    Json.arrayString(contact.phones),
                    contact.notes,
                    contact.source,
                    contact.externalId,
                    SqlTimestamp.encode(contact.createdAt),
                    SqlTimestamp.encode(contact.updatedAt),
                    contact.deletedAt.map(SqlTimestamp.encode),
                    contact.version,
                    contact.deviceId,
                ]
            )
        }
    }

    public func delete(_ id: UUIDv7, at: Date) async throws {
        try await queue.write { db in
            let stamp = SqlTimestamp.encode(at)
            try db.execute(
                sql: """
                    UPDATE contact
                    SET deleted_at = ?, updated_at = ?, version = version + 1
                    WHERE id = ?
                    """,
                arguments: [stamp, stamp, id.uuid.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM contact_group_member WHERE contact_id = ?",
                arguments: [id.uuid.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM task_contact WHERE contact_id = ?",
                arguments: [id.uuid.uuidString]
            )
        }
    }

    public func groups() async -> [ContactGroup] {
        (try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM contact_group ORDER BY sort_order, name COLLATE NOCASE"
            ).map { ContactGroupRecord(row: $0).model }
        }) ?? []
    }

    public func saveGroup(_ group: ContactGroup) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO contact_group (
                      id, name, color_hex, sort_order,
                      created_at, updated_at, version, device_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      name = excluded.name,
                      color_hex = excluded.color_hex,
                      sort_order = excluded.sort_order,
                      updated_at = excluded.updated_at,
                      version = excluded.version,
                      device_id = excluded.device_id
                    """,
                arguments: [
                    group.id.uuid.uuidString,
                    group.name,
                    group.colorHex,
                    group.sortOrder,
                    SqlTimestamp.encode(group.createdAt),
                    SqlTimestamp.encode(group.updatedAt),
                    group.version,
                    group.deviceId,
                ]
            )
        }
    }

    public func deleteGroup(_ id: UUIDv7) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM contact_group_member WHERE group_id = ?",
                arguments: [id.uuid.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM contact_group WHERE id = ?",
                arguments: [id.uuid.uuidString]
            )
        }
    }

    public func groupIds(for contactId: UUIDv7) async -> [UUIDv7] {
        (try? await queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT group_id FROM contact_group_member WHERE contact_id = ?",
                arguments: [contactId.uuid.uuidString]
            ).map(UUIDv7.init(databaseString:))
        }) ?? []
    }

    public func setGroups(_ groupIds: [UUIDv7], for contactId: UUIDv7) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM contact_group_member WHERE contact_id = ?",
                arguments: [contactId.uuid.uuidString]
            )
            for groupId in Set(groupIds) {
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO contact_group_member (contact_id, group_id)
                        VALUES (?, ?)
                        """,
                    arguments: [contactId.uuid.uuidString, groupId.uuid.uuidString]
                )
            }
        }
    }

    public func contacts(inGroup groupId: UUIDv7) async -> [Contact] {
        (try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT c.* FROM contact c
                    JOIN contact_group_member m ON m.contact_id = c.id
                    WHERE m.group_id = ? AND c.deleted_at IS NULL
                    ORDER BY c.last_name COLLATE NOCASE, c.first_name COLLATE NOCASE
                    """,
                arguments: [groupId.uuid.uuidString]
            ).map { ContactRecord(row: $0).model }
        }) ?? []
    }

    public func contacts(forTask taskId: UUIDv7) async -> [Contact] {
        (try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT c.* FROM contact c
                    JOIN task_contact t ON t.contact_id = c.id
                    WHERE t.task_id = ? AND c.deleted_at IS NULL
                    ORDER BY c.last_name COLLATE NOCASE, c.first_name COLLATE NOCASE
                    """,
                arguments: [taskId.uuid.uuidString]
            ).map { ContactRecord(row: $0).model }
        }) ?? []
    }

    public func taskIds(forContact contactId: UUIDv7) async -> [UUIDv7] {
        (try? await queue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT task_id FROM task_contact WHERE contact_id = ?",
                arguments: [contactId.uuid.uuidString]
            ).map(UUIDv7.init(databaseString:))
        }) ?? []
    }

    public func addContact(_ contactId: UUIDv7, toTask taskId: UUIDv7) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO task_contact (task_id, contact_id, created_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    taskId.uuid.uuidString,
                    contactId.uuid.uuidString,
                    SqlTimestamp.encode(Date()),
                ]
            )
        }
    }

    public func removeContact(_ contactId: UUIDv7, fromTask taskId: UUIDv7) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM task_contact WHERE task_id = ? AND contact_id = ?",
                arguments: [taskId.uuid.uuidString, contactId.uuid.uuidString]
            )
        }
    }

    public func merge(_ sourceIds: [UUIDv7], into primary: Contact, at: Date) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO contact (
                      id, first_name, last_name, company, job_title,
                      emails_json, phones_json, notes, source, external_id,
                      created_at, updated_at, deleted_at, version, device_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      first_name = excluded.first_name,
                      last_name = excluded.last_name,
                      company = excluded.company,
                      job_title = excluded.job_title,
                      emails_json = excluded.emails_json,
                      phones_json = excluded.phones_json,
                      notes = excluded.notes,
                      source = excluded.source,
                      external_id = excluded.external_id,
                      updated_at = excluded.updated_at,
                      deleted_at = excluded.deleted_at,
                      version = excluded.version,
                      device_id = excluded.device_id
                    """,
                arguments: [
                    primary.id.uuid.uuidString,
                    primary.firstName,
                    primary.lastName,
                    primary.company,
                    primary.jobTitle,
                    Json.arrayString(primary.emails),
                    Json.arrayString(primary.phones),
                    primary.notes,
                    primary.source,
                    primary.externalId,
                    SqlTimestamp.encode(primary.createdAt),
                    SqlTimestamp.encode(primary.updatedAt),
                    primary.deletedAt.map(SqlTimestamp.encode),
                    primary.version,
                    primary.deviceId,
                ]
            )

            let sourceStrings = sourceIds
                .filter { $0 != primary.id }
                .map { $0.uuid.uuidString }
            guard !sourceStrings.isEmpty else { return }
            let placeholders = Array(repeating: "?", count: sourceStrings.count)
                .joined(separator: ",")

            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO contact_group_member (contact_id, group_id)
                    SELECT ?, group_id FROM contact_group_member
                    WHERE contact_id IN (\(placeholders))
                    """,
                arguments: StatementArguments([primary.id.uuid.uuidString] + sourceStrings)
            )
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO task_contact (task_id, contact_id, created_at)
                    SELECT task_id, ?, created_at FROM task_contact
                    WHERE contact_id IN (\(placeholders))
                    """,
                arguments: StatementArguments([primary.id.uuid.uuidString] + sourceStrings)
            )
            try db.execute(
                sql: "DELETE FROM contact_group_member WHERE contact_id IN (\(placeholders))",
                arguments: StatementArguments(sourceStrings)
            )
            try db.execute(
                sql: "DELETE FROM task_contact WHERE contact_id IN (\(placeholders))",
                arguments: StatementArguments(sourceStrings)
            )
            let stamp = SqlTimestamp.encode(at)
            try db.execute(
                sql: """
                    UPDATE contact
                    SET deleted_at = ?, updated_at = ?, version = version + 1
                    WHERE id IN (\(placeholders))
                    """,
                arguments: StatementArguments([stamp, stamp] + sourceStrings)
            )
        }
    }
}
