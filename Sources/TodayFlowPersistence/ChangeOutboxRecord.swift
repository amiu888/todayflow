import Foundation
import GRDB

/// A row of the `change_outbox` table — the queue the sync engine consumes
/// (driver.md §6: v1 fills the outbox but never consumes it; increment 8's
/// `NoopSyncEngine` will).
///
/// Public because the sync target (increment 8) reads it; it carries no GRDB
/// types so the library's public API stays GRDB-free.
public struct ChangeOutboxRecord: Sendable {
    public let seq: Int64
    public let entity: String
    public let entityId: String
    /// `"upsert"` or `"delete"`.
    public let op: String
    public let payloadJson: String
    public let createdAt: Date
    public let syncedAt: Date?

    init(row: Row) {
        seq = row["seq"] as Int64
        entity = row["entity"] as String
        entityId = row["entity_id"] as String
        op = row["op"] as String
        payloadJson = row["payload_json"] as String
        createdAt = SqlTimestamp.decode(row["created_at"] as String) ?? .distantPast
        syncedAt = (row["synced_at"] as String?).flatMap(SqlTimestamp.decode)
    }
}
