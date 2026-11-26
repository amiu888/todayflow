import Foundation
import TodayFlowCore

/// A table that syncs with the TodayFlow server.
public struct SyncTable: Sendable, Equatable {
    /// The table name; also the `entity` on the wire.
    public let name: String
    /// Primary-key columns. A composite key is sent as the values joined by `|`.
    public let key: [String]
    /// Columns that only make sense on this Mac (file bookmarks, local copies).
    /// They are never sent and never overwritten by a remote change.
    public let localOnly: Set<String>
    /// When set, only rows with one of these keys sync (the `setting` table
    /// shares only the trays; everything else stays on the device).
    public let onlyRows: Set<String>?

    public init(_ name: String, key: [String] = ["id"], localOnly: Set<String> = [], onlyRows: Set<String>? = nil) {
        self.name = name
        self.key = key
        self.localOnly = localOnly
        self.onlyRows = onlyRows
    }

    /// Whether the row with this id syncs.
    public func syncs(rowId: String) -> Bool {
        onlyRows.map { $0.contains(rowId) } ?? true
    }

    /// SQL for the row id, from `NEW` or `OLD` in a trigger.
    func idExpression(_ row: String) -> String {
        key.map { "\(row).\($0)" }.joined(separator: " || '|' || ")
    }
}

/// Settings shared by all of a user's devices: the working trays and their
/// rules. Everything else in `setting` (sync pairing, AI, work hours, window
/// choices) belongs to one device.
public enum SyncedSettings {
    public static let keys: Set<String> = [SettingKeys.workTrays, SettingKeys.workflowRules]
}

/// The synced tables, parents before children. Other settings, the activity
/// search index and the old `change_outbox` stay on this device.
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
        SyncTable("setting", key: ["key"], onlyRows: SyncedSettings.keys),
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

    /// v11: the working trays and tray rules sync (two rows of `setting`).
    /// A device that is already paired queues its current trays once, so they
    /// reach the user's other devices; an unpaired device waits for pairing,
    /// where the server's copy wins (see `SyncStore.markAllPending`).
    ///
    /// Frozen like v9: the keys are spelled out.
    static let schemaV11: String = {
        let keys = "('work_trays', 'workflow_rules')"
        var sql = ""
        for (suffix, event, row) in [("ai", "INSERT", "NEW"), ("au", "UPDATE", "NEW"), ("ad", "DELETE", "OLD")] {
            sql += """
                CREATE TRIGGER sync_setting_\(suffix) AFTER \(event) ON setting
                WHEN (SELECT applying FROM sync_flag) = 0 AND \(row).key IN \(keys)
                BEGIN
                  DELETE FROM sync_change WHERE entity = 'setting' AND row_id = \(row).key;
                  INSERT INTO sync_change (entity, row_id, changed_at)
                  VALUES ('setting', \(row).key, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
                END;

                """
        }
        sql += """
            INSERT OR IGNORE INTO sync_change (entity, row_id, changed_at)
            SELECT 'setting', key, strftime('%Y-%m-%dT%H:%M:%fZ', 'now') FROM setting
            WHERE key IN \(keys)
              AND EXISTS (SELECT 1 FROM sync_state WHERE key = 'cursor');
            """
        return sql
    }()

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
