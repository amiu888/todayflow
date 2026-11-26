import Foundation
import GRDB

/// One column value on the wire. Rows travel as plain JSON objects.
public enum SyncValue: Codable, Sendable, Equatable {
    case null
    case int(Int64)
    case double(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = value.rounded() == value && abs(value) < 9e15 ? .int(Int64(value)) : .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .int(value ? 1 : 0)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    var databaseValue: DatabaseValue {
        switch self {
        case .null: return .null
        case .int(let value): return value.databaseValue
        case .double(let value): return value.databaseValue
        case .string(let value): return value.databaseValue
        }
    }

    /// Nil for blobs, which never sync.
    init?(_ value: DatabaseValue) {
        switch value.storage {
        case .null: self = .null
        case .int64(let value): self = .int(value)
        case .double(let value): self = .double(value)
        case .string(let value): self = .string(value)
        case .blob: return nil
        }
    }
}

public typealias SyncRow = [String: SyncValue]

/// A change to one row, as pushed to and pulled from the server. Pulled
/// changes carry more fields (`seq`, `deviceId`), which are ignored.
public struct SyncChange: Codable, Sendable, Equatable {
    public var entity: String
    public var id: String
    /// "upsert" or "delete".
    public var op: String
    /// ISO 8601 UTC with milliseconds; the newest change to a row wins.
    public var changedAt: String
    /// The whole row for an upsert.
    public var data: SyncRow?

    public init(entity: String, id: String, op: String, changedAt: String, data: SyncRow?) {
        self.entity = entity
        self.id = id
        self.op = op
        self.changedAt = changedAt
        self.data = data
    }
}

/// The local side of sync: reads recorded changes, applies remote ones, and
/// keeps the pull cursor. Every remote change is applied with recording off,
/// so it is never sent back.
public final class SyncStore: Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - Outgoing

    /// The oldest recorded local changes, with each row's current data. A row
    /// that no longer exists is sent as a delete.
    public func pendingChanges(limit: Int = 200) async throws -> [SyncChange] {
        try await queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT entity, row_id, changed_at FROM sync_change ORDER BY changed_at, entity, row_id LIMIT ?",
                arguments: [limit]
            )
            return try rows.compactMap { row -> SyncChange? in
                let entity: String = row["entity"]
                let id: String = row["row_id"]
                let changedAt: String = row["changed_at"]
                guard let table = SyncTables.named(entity) else { return nil }
                if let data = try Self.rowData(db, table: table, id: id) {
                    return SyncChange(entity: entity, id: id, op: "upsert", changedAt: changedAt, data: data)
                }
                return SyncChange(entity: entity, id: id, op: "delete", changedAt: changedAt, data: nil)
            }
        }
    }

    /// Re-dates pending changes stamped in the future to now. Returns how
    /// many were changed.
    @discardableResult
    public func clampFutureChanges() async throws -> Int {
        try await queue.write { db in
            try db.execute(sql: """
                UPDATE sync_change SET changed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
                WHERE changed_at > strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
                """)
            return db.changesCount
        }
    }

    public func pendingCount() async throws -> Int {
        try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_change") ?? 0
        }
    }

    /// Forgets changes the server accepted. A row edited again since it was
    /// read has a newer time and stays pending.
    public func markPushed(_ changes: [SyncChange]) async throws {
        try await queue.write { db in
            for change in changes {
                try db.execute(
                    sql: "DELETE FROM sync_change WHERE entity = ? AND row_id = ? AND changed_at = ?",
                    arguments: [change.entity, change.id, change.changedAt]
                )
            }
        }
    }

    /// First sync: every existing row becomes pending, dated by its own
    /// `updated_at` (or `created_at`), so older edits never beat newer ones
    /// from another Mac.
    public func markAllPending() async throws {
        try await queue.write { db in
            for table in SyncTables.all {
                let columns = try Set(db.columns(in: table.name).map(\.name))
                // Never later than now: a row stamped in the future (an
                // import, a Mac whose clock was once ahead) would be refused
                // by the server and would beat every real edit.
                let now = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"
                let time = ["updated_at", "created_at", "occurred_at"].first(where: columns.contains)
                    .map { "MIN(COALESCE(\($0), \(now)), \(now))" }
                    ?? now
                if let only = table.onlyRows {
                    // Shared settings (trays) join the account's existing
                    // copy: dated at the epoch, the server's version wins, so
                    // a new device's empty default never replaces real trays.
                    let list = only.sorted().map { "'\($0)'" }.joined(separator: ", ")
                    try db.execute(sql: """
                        INSERT OR REPLACE INTO sync_change (entity, row_id, changed_at)
                        SELECT '\(table.name)', "\(table.key[0])", '1970-01-01T00:00:00.000Z'
                        FROM "\(table.name)" WHERE "\(table.key[0])" IN (\(list))
                        """)
                    continue
                }
                try db.execute(sql: """
                    INSERT OR IGNORE INTO sync_change (entity, row_id, changed_at)
                    SELECT '\(table.name)', \(table.key.map { "\"\($0)\"" }.joined(separator: " || '|' || ")), \(time)
                    FROM "\(table.name)"
                    """)
            }
        }
    }

    // MARK: - Incoming

    /// Applies pulled changes in one transaction and stores the new cursor.
    /// A row with a newer local change is skipped (that change will be pushed
    /// and win on the server). Returns how many rows changed.
    @discardableResult
    public func apply(_ changes: [SyncChange], cursor: Int64? = nil) async throws -> Int {
        try await applyChanges(changes, cursor: cursor).count
    }

    /// Like `apply`, returning the changes that actually changed a row.
    public func applyChanges(_ changes: [SyncChange], cursor: Int64? = nil) async throws -> [SyncChange] {
        try await queue.writeWithoutTransaction { db in
            // Rows can arrive before their parents; references are restored by
            // later changes, so foreign keys are not enforced while applying.
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            defer { try? db.execute(sql: "PRAGMA foreign_keys = ON") }
            var applied: [SyncChange] = []
            try db.inTransaction {
                try db.execute(sql: "UPDATE sync_flag SET applying = 1")
                for change in changes where try Self.apply(change, db) {
                    applied.append(change)
                }
                if let cursor {
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO sync_state (key, value) VALUES ('cursor', ?)",
                        arguments: [String(cursor)]
                    )
                }
                try db.execute(sql: "UPDATE sync_flag SET applying = 0")
                return .commit
            }
            return applied
        }
    }

    /// The server sequence number pulled up to.
    public func cursor() async throws -> Int64 {
        try await queue.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM sync_state WHERE key = 'cursor'")
                .flatMap { Int64($0) } ?? 0
        }
    }

    /// Starts pulling from the beginning again (after pairing with a server).
    public func resetCursor() async throws {
        try await queue.write { db in
            try db.execute(sql: "DELETE FROM sync_state WHERE key = 'cursor'")
        }
    }

    // MARK: - Rows

    static func keyValues(_ table: SyncTable, id: String) -> [String]? {
        let parts = table.key.count == 1 ? [id] : id.components(separatedBy: "|")
        return parts.count == table.key.count ? parts : nil
    }

    static func rowData(_ db: Database, table: SyncTable, id: String) throws -> SyncRow? {
        guard let keys = keyValues(table, id: id) else { return nil }
        let condition = table.key.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM \"\(table.name)\" WHERE \(condition)",
            arguments: StatementArguments(keys)
        ) else { return nil }
        var data: SyncRow = [:]
        for (column, value) in row where !table.localOnly.contains(column) {
            if let synced = SyncValue(value) { data[column] = synced }
        }
        return data
    }

    private static func apply(_ change: SyncChange, _ db: Database) throws -> Bool {
        guard let table = SyncTables.named(change.entity),
              table.syncs(rowId: change.id),
              let keys = keyValues(table, id: change.id)
        else { return false }

        let local = try String.fetchOne(
            db,
            sql: "SELECT changed_at FROM sync_change WHERE entity = ? AND row_id = ?",
            arguments: [change.entity, change.id]
        )
        if let local, local > change.changedAt { return false }
        if local != nil {
            try db.execute(
                sql: "DELETE FROM sync_change WHERE entity = ? AND row_id = ?",
                arguments: [change.entity, change.id]
            )
        }

        if change.op == "delete" {
            let condition = table.key.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
            try db.execute(
                sql: "DELETE FROM \"\(table.name)\" WHERE \(condition)",
                arguments: StatementArguments(keys)
            )
            return db.changesCount > 0
        }

        guard let data = change.data else { return false }
        let columns = try db.columns(in: table.name).map(\.name)
            .filter { data[$0] != nil && !table.localOnly.contains($0) }
        guard table.key.allSatisfy(columns.contains) else { return false }
        let others = columns.filter { !table.key.contains($0) }
        let condition = table.key.map { "\"\($0)\" = ?" }.joined(separator: " AND ")
        do {
            // Update first, so a row with columns this Mac doesn't know (or
            // lacks) still merges; insert only when the row is new here.
            if !others.isEmpty {
                try db.execute(
                    sql: "UPDATE \"\(table.name)\" SET \(others.map { "\"\($0)\" = ?" }.joined(separator: ", ")) WHERE \(condition)",
                    arguments: StatementArguments(others.map { data[$0]!.databaseValue } + keys.map { $0.databaseValue })
                )
                if db.changesCount > 0 { return true }
            } else if try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM \"\(table.name)\" WHERE \(condition)",
                arguments: StatementArguments(keys)
            ) == true {
                return false
            }
            try db.execute(
                sql: "INSERT INTO \"\(table.name)\" (\(columns.map { "\"\($0)\"" }.joined(separator: ", "))) VALUES (\(Array(repeating: "?", count: columns.count).joined(separator: ", ")))",
                arguments: StatementArguments(columns.map { data[$0]!.databaseValue })
            )
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            // For example the same link made on two Macs under different ids:
            // keep the local one.
            return false
        }
        return true
    }
}

// MARK: - Attachment files

/// An attachment's file state, for uploading and downloading its bytes.
public struct SyncAttachmentFile: Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var kind: String
    public var reference: String
    public var localCopyPath: String?
    public var blobSHA256: String?
    public var blobSize: Int?

    /// A copy kept inside TodayFlow exists.
    public var hasOwnCopy: Bool {
        guard let copy = localCopyPath, !copy.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: copy)
    }

    /// True when this Mac already has the file the row names: its own copy,
    /// or the original path holding a file of the same size.
    public var hasLocalBytes: Bool {
        if hasOwnCopy { return true }
        guard reference.hasPrefix("/"), let blobSize,
              let size = (try? FileManager.default.attributesOfItem(atPath: reference))?[.size] as? NSNumber
        else { return false }
        return size.intValue == blobSize
    }

    /// A file on this Mac that holds the attachment's bytes, if any.
    public var localFile: URL? {
        for path in [localCopyPath, reference.hasPrefix("/") ? reference : nil].compactMap({ $0 }) where !path.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

extension SyncStore {
    /// Live attachments whose file has not been uploaded and was not skipped.
    public func attachmentsWithoutBlob() async throws -> [SyncAttachmentFile] {
        try await attachmentFiles(where: """
            blob_sha256 IS NULL AND deleted_at IS NULL
            AND id NOT IN (SELECT attachment_id FROM sync_blob_skip)
            """)
    }

    /// Live attachments that name a file on the server.
    public func attachmentsWithBlob() async throws -> [SyncAttachmentFile] {
        try await attachmentFiles(where: "blob_sha256 IS NOT NULL AND deleted_at IS NULL")
    }

    /// Stores the uploaded file's hash. Recorded as a change, so the row is
    /// pushed with it and other Macs learn which file to fetch.
    public func setBlob(attachmentId: String, sha256: String, size: Int) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "UPDATE attachment SET blob_sha256 = ?, blob_size = ? WHERE id = ?",
                arguments: [sha256, size, attachmentId]
            )
        }
    }

    /// Points the attachment at a downloaded copy. Local only: not recorded.
    public func setLocalCopy(attachmentId: String, path: String) async throws {
        try await queue.write { db in
            try db.execute(sql: "UPDATE sync_flag SET applying = 1")
            try db.execute(
                sql: "UPDATE attachment SET local_copy_path = ? WHERE id = ?",
                arguments: [path, attachmentId]
            )
            try db.execute(sql: "UPDATE sync_flag SET applying = 0")
        }
    }

    /// Stops retrying a file this Mac can't upload.
    public func skipBlob(attachmentId: String, reason: String, fileSize: Int?) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_blob_skip (attachment_id, reason, file_size, tried_at) VALUES (?, ?, ?, ?)",
                arguments: [attachmentId, reason, fileSize, SqlTimestamp.encode(.now)]
            )
        }
    }

    /// Files skipped on this Mac, with the reason (for Settings ▸ Sync).
    public func skippedBlobs() async throws -> [(name: String, reason: String)] {
        try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT a.display_name AS name, s.reason AS reason
                FROM sync_blob_skip s JOIN attachment a ON a.id = s.attachment_id
                WHERE a.deleted_at IS NULL ORDER BY a.display_name
                """).map { ($0["name"], $0["reason"]) }
        }
    }

    private func attachmentFiles(where condition: String) async throws -> [SyncAttachmentFile] {
        try await queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, display_name, type, reference, local_copy_path, blob_sha256, blob_size
                FROM attachment WHERE \(condition) ORDER BY created_at
                """).map {
                SyncAttachmentFile(
                    id: $0["id"], displayName: $0["display_name"], kind: $0["type"],
                    reference: $0["reference"] ?? "", localCopyPath: $0["local_copy_path"],
                    blobSHA256: $0["blob_sha256"], blobSize: $0["blob_size"]
                )
            }
        }
    }
}
