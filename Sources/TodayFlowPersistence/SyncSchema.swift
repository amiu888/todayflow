import Foundation

/// A table that syncs with the TodayFlow server.
public struct SyncTable: Sendable, Equatable {
    /// The table name; also the `entity` on the wire.
    public let name: String
    /// Primary-key columns. A composite key is sent as the values joined by `|`.
    public let key: [String]
    /// Columns that only make sense on this Mac (file bookmarks, local copies).
    /// They are never sent and never overwritten by a remote change.
    public let localOnly: Set<String>

    public init(_ name: String, key: [String] = ["id"], localOnly: Set<String> = []) {
        self.name = name
        self.key = key
        self.localOnly = localOnly
    }

    /// SQL for the row id, from `NEW` or `OLD` in a trigger.
    func idExpression(_ row: String) -> String {
        key.map { "\(row).\($0)" }.joined(separator: " || '|' || ")
    }
}

/// The synced tables, parents before children. Settings, the activity search
/// index and the old `change_outbox` stay on this Mac.
public enum SyncTables {
    public static let all: [SyncTable] = [
        SyncTable("work_item"),
        SyncTable("contact"),
        SyncTable("contact_group"),
        SyncTable("action_item"),
        SyncTable("attachment", localOnly: ["bookmark", "local_copy_path"]),
        SyncTable("item_link"),
        SyncTable("reminder"),
        SyncTable("activity"),
        SyncTable("contact_group_member", key: ["contact_id", "group_id"]),
        SyncTable("task_contact", key: ["task_id", "contact_id"]),
    ]

    public static func named(_ name: String) -> SyncTable? {
        all.first { $0.name == name }
    }
}

extension TodayFlowMigrations {
    /// v9: change tracking for sync.
    ///
    /// (A trigger deletes then inserts: an outer UPSERT would override an
    /// `OR REPLACE` inside the trigger.)
    /// Triggers record every insert, update and delete on a synced table in
    /// `sync_change` (one row per changed record, newest time wins). While
    /// remote changes are applied, `sync_flag.applying` is 1 and nothing is
    /// recorded, so changes never echo back to the server.
    ///
    /// Frozen: the table list is spelled out here, not read from
    /// `SyncTables`, so later edits there never change a shipped migration.
    static var schemaV9: String {
        let tables: [(String, [String])] = [
            ("work_item", ["id"]), ("contact", ["id"]), ("contact_group", ["id"]),
            ("action_item", ["id"]), ("attachment", ["id"]), ("item_link", ["id"]),
            ("reminder", ["id"]), ("activity", ["id"]),
            ("contact_group_member", ["contact_id", "group_id"]),
            ("task_contact", ["task_id", "contact_id"]),
        ]
        var sql = """
            CREATE TABLE sync_change (
              entity TEXT NOT NULL,
              row_id TEXT NOT NULL,
              changed_at TEXT NOT NULL,
              PRIMARY KEY (entity, row_id)
            );
            CREATE TABLE sync_flag (applying INTEGER NOT NULL);
            INSERT INTO sync_flag (applying) VALUES (0);
            CREATE TABLE sync_state (key TEXT PRIMARY KEY, value TEXT NOT NULL);

            """
        for (name, key) in tables {
            let table = SyncTable(name, key: key)
            for (suffix, event, row) in [("ai", "INSERT", "NEW"), ("au", "UPDATE", "NEW"), ("ad", "DELETE", "OLD")] {
                sql += """
                    CREATE TRIGGER sync_\(name)_\(suffix) AFTER \(event) ON \(name)
                    WHEN (SELECT applying FROM sync_flag) = 0
                    BEGIN
                      DELETE FROM sync_change WHERE entity = '\(name)' AND row_id = \(table.idExpression(row));
                      INSERT INTO sync_change (entity, row_id, changed_at)
                      VALUES ('\(name)', \(table.idExpression(row)), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
                    END;

                    """
            }
        }
        return sql
    }

    /// v10: attachment files travel too. `blob_sha256`/`blob_size` sync with
    /// the row and name the file on the server; `sync_blob_skip` remembers
    /// files this Mac can't upload (too big, unreadable) so it stops retrying.
    static let schemaV10 = """
        ALTER TABLE attachment ADD COLUMN blob_sha256 TEXT;
        ALTER TABLE attachment ADD COLUMN blob_size INTEGER;
        CREATE TABLE sync_blob_skip (
          attachment_id TEXT PRIMARY KEY,
          reason TEXT NOT NULL,
          file_size INTEGER,
          tried_at TEXT NOT NULL
        );
        """
}
