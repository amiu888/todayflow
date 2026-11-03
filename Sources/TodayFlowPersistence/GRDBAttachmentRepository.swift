import Foundation
import GRDB
import TodayFlowCore

/// The GRDB adapter for `AttachmentRepository` (driver.md §6, §11).
///
/// - `save` is an upsert keyed on `id`; the FTS triggers in the schema keep
///   `search_index.attachments` in step automatically.
/// - `delete` is a **hard** delete (the model has no `deletedAt`) and appends a
///   `"delete"` outbox row in the same transaction.
public final class GRDBAttachmentRepository: AttachmentRepository, Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - Reads (non-throwing per the port contract)

    public func attachments(for itemId: UUIDv7) async -> [Attachment] {
        let attachments = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM attachment
                    WHERE work_item_id = ? AND deleted_at IS NULL
                    ORDER BY created_at
                    """,
                arguments: [itemId.uuid.uuidString]
            ).map { AttachmentRecord(row: $0).model }
        }
        return attachments ?? []
    }

    // MARK: - Mutations (throwing per the port contract)

    public func save(_ attachment: Attachment) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO attachment (
                      id, work_item_id, type, uti, display_name, source_app, reference,
                      bookmark, local_copy_path, metadata_json, preview_text,
                      created_at, updated_at, deleted_at, version
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      work_item_id = excluded.work_item_id,
                      type = excluded.type,
                      uti = excluded.uti,
                      display_name = excluded.display_name,
                      source_app = excluded.source_app,
                      reference = excluded.reference,
                      bookmark = excluded.bookmark,
                      local_copy_path = excluded.local_copy_path,
                      metadata_json = excluded.metadata_json,
                      preview_text = excluded.preview_text,
                      deleted_at = NULL,
                      version = excluded.version
                    """,
                arguments: [
                    attachment.id.uuid.uuidString,
                    attachment.itemId.uuid.uuidString,
                    attachment.kind.dbValue,
                    attachment.uti,
                    attachment.displayName,
                    attachment.sourceApp,
                    attachment.reference ?? "",
                    attachment.bookmark,
                    attachment.localCopyPath,
                    Json.objectString(attachment.metadata),
                    attachment.previewText,
                    SqlTimestamp.encode(attachment.createdAt),
                    SqlTimestamp.encode(attachment.createdAt),
                    attachment.version,
                ]
            )
            try Outbox.append(
                db,
                entity: "attachment",
                entityId: attachment.id.uuid.uuidString,
                op: "upsert",
                payloadJson: (try? Json.encode(attachment)) ?? "{}",
                at: attachment.createdAt
            )
        }
    }

    public func delete(_ id: UUIDv7) async throws {
        try await queue.write { db in
            let idString = id.uuid.uuidString
            try db.execute(
                sql: "DELETE FROM attachment WHERE id = ?",
                arguments: [idString]
            )
            try Outbox.append(
                db,
                entity: "attachment",
                entityId: idString,
                op: "delete",
                payloadJson: "{}",
                at: .now
            )
        }
    }
}
