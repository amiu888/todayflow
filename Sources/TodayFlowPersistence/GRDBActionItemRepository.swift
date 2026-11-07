import Foundation
import GRDB
import TodayFlowCore

/// GRDB adapter for the `action_item` checklist table.
public final class GRDBActionItemRepository: ActionItemRepository, Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    public func actions(for itemId: UUIDv7) async -> [ActionItem] {
        let actions = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM action_item
                    WHERE work_item_id = ? AND deleted_at IS NULL
                    ORDER BY sort_order, created_at
                    """,
                arguments: [itemId.uuid.uuidString]
            ).map { ActionItemRecord(row: $0).model }
        }
        return actions ?? []
    }

    public func save(_ action: ActionItem) async throws {
        let updated = SqlTimestamp.encode(Date())
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO action_item (
                      id, work_item_id, text, is_done, sort_order,
                      created_at, updated_at, deleted_at, version
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      work_item_id = excluded.work_item_id,
                      text = excluded.text,
                      is_done = excluded.is_done,
                      sort_order = excluded.sort_order,
                      updated_at = excluded.updated_at,
                      deleted_at = NULL,
                      version = excluded.version
                    """,
                arguments: [
                    action.id.uuid.uuidString,
                    action.itemId.uuid.uuidString,
                    action.text,
                    action.isDone ? 1 : 0,
                    String(action.sortOrder),
                    SqlTimestamp.encode(action.createdAt),
                    updated,
                    action.version,
                ]
            )
        }
    }

    public func delete(_ id: UUIDv7) async throws {
        let now = SqlTimestamp.encode(Date())
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE action_item SET deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [now, now, id.uuid.uuidString]
            )
        }
    }
}
