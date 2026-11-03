import Foundation
import GRDB
import TodayFlowCore

/// The GRDB adapter for `LinkRepository` (driver.md §6, §11).
///
/// - `save` is an upsert keyed on `id`; the `UNIQUE (from_id, to_id, type)`
///   constraint plus the two partial unique indexes (`uq_blocks_out` /
///   `uq_blocks_in`) enforce the one-way linked-list shape of `blocks` chains
///   at the database level, so a duplicate active `blocks` link throws.
/// - `delete` is a **hard** delete (the model has no `deletedAt`) and appends a
///   `"delete"` outbox row in the same transaction.
public final class GRDBLinkRepository: LinkRepository, Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - Reads (non-throwing per the port contract)

    public func links(from id: UUIDv7) async -> [ItemLink] {
        let links = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM item_link WHERE from_id = ? AND deleted_at IS NULL",
                arguments: [id.uuid.uuidString]
            ).map { ItemLinkRecord(row: $0).model }
        }
        return links ?? []
    }

    public func links(to id: UUIDv7) async -> [ItemLink] {
        let links = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM item_link WHERE to_id = ? AND deleted_at IS NULL",
                arguments: [id.uuid.uuidString]
            ).map { ItemLinkRecord(row: $0).model }
        }
        return links ?? []
    }

    public func allLinks() async -> [ItemLink] {
        let links = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM item_link WHERE deleted_at IS NULL"
            ).map { ItemLinkRecord(row: $0).model }
        }
        return links ?? []
    }

    // MARK: - Mutations (throwing per the port contract)

    public func save(_ link: ItemLink) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO item_link (
                      id, from_id, to_id, type, created_at, updated_at, deleted_at, version
                    ) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      from_id = excluded.from_id,
                      to_id = excluded.to_id,
                      type = excluded.type,
                      deleted_at = NULL,
                      version = excluded.version
                    """,
                arguments: [
                    link.id.uuid.uuidString,
                    link.fromId.uuid.uuidString,
                    link.toId.uuid.uuidString,
                    link.kind.dbValue,
                    SqlTimestamp.encode(link.createdAt),
                    SqlTimestamp.encode(link.createdAt),
                    link.version,
                ]
            )
            try Outbox.append(
                db,
                entity: "item_link",
                entityId: link.id.uuid.uuidString,
                op: "upsert",
                payloadJson: (try? Json.encode(link)) ?? "{}",
                at: link.createdAt
            )
        }
    }

    public func delete(_ id: UUIDv7) async throws {
        try await queue.write { db in
            let idString = id.uuid.uuidString
            try db.execute(
                sql: "DELETE FROM item_link WHERE id = ?",
                arguments: [idString]
            )
            try Outbox.append(
                db,
                entity: "item_link",
                entityId: idString,
                op: "delete",
                payloadJson: "{}",
                at: .now
            )
        }
    }
}
