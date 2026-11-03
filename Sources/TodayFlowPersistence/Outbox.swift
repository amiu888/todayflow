import Foundation
import GRDB
import TodayFlowCore

/// Appends rows to the `change_outbox` table (driver.md §6: "every write appends
/// a `change_outbox` row in the same transaction").
///
/// `append` takes the open `Database` connection so callers can run it inside the
/// same transaction as the write it describes — the sync engine (increment 8)
/// relies on that atomicity.
enum Outbox {
    static func append(
        _ db: Database,
        entity: String,
        entityId: String,
        op: String,
        payloadJson: String,
        at: Date
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO change_outbox (entity, entity_id, op, payload_json, created_at, synced_at)
                VALUES (?, ?, ?, ?, ?, NULL)
                """,
            arguments: [entity, entityId, op, payloadJson, SqlTimestamp.encode(at)]
        )
    }
}

/// Reads and marks the `change_outbox` — the surface the sync engine consumes.
///
/// v1 never consumes it (driver.md §6: "v1 = local only, outbox filled but not
/// consumed, `NoopSyncEngine`"); increment 8's sync target builds on this.
public final class OutboxStore: Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    /// All outbox rows not yet synced, oldest first.
    public func pending() async throws -> [ChangeOutboxRecord] {
        try await queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM change_outbox WHERE synced_at IS NULL ORDER BY seq"
            )
            return rows.map { ChangeOutboxRecord(row: $0) }
        }
    }

    /// Stamps the given outbox rows as synced.
    public func markSynced(_ seqs: [Int64], at: Date) async throws {
        try await queue.write { db in
            let stamp = SqlTimestamp.encode(at)
            for seq in seqs {
                try db.execute(
                    sql: "UPDATE change_outbox SET synced_at = ? WHERE seq = ?",
                    arguments: [stamp, seq]
                )
            }
        }
    }
}
