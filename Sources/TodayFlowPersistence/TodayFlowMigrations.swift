import Foundation
import GRDB

/// Versioned GRDB migrations for the TodayFlow database (driver.md §6).
///
/// "Database changes only through versioned GRDB migrations; never edit a shipped
/// migration" (driver.md §6). Schema v1 is the full driver.md §6 schema, applied
/// as a single multi-statement `execute`.
public enum TodayFlowMigrations {
    /// The v1 migrator. Kept for migration tests and historical clarity.
    public static var v1: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: schemaV1)
        }
        return migrator
    }

    /// All migrations through the current schema. New databases and upgrades
    /// both use this; shipped migrations are never edited.
    public static var current: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: schemaV1)
        }
        migrator.registerMigration("v2") { db in
            try db.execute(sql: schemaV2)
        }
        migrator.registerMigration("v3") { db in
            try db.execute(sql: schemaV3)
        }
        migrator.registerMigration("v4") { db in
            try db.execute(sql: schemaV4)
        }
        migrator.registerMigration("v5") { db in
            try db.execute(sql: schemaV5)
        }
        return migrator
    }

    /// v5 adds the task summary (AI-generated from an email or written by hand).
    static let schemaV5 = """
        ALTER TABLE work_item ADD COLUMN summary TEXT NOT NULL DEFAULT '';
        """

    /// v4 adds a user description per attachment.
    static let schemaV4 = """
        ALTER TABLE attachment ADD COLUMN note TEXT;
        """

    /// v3 adds optional effort estimates for the daily load meter.
    static let schemaV3 = """
        ALTER TABLE work_item ADD COLUMN estimated_minutes INTEGER;
        """

    /// v2 adds the append-only activity/audit log (FR-20).
    static let schemaV2 = """
        CREATE TABLE activity (
          id TEXT PRIMARY KEY,
          work_item_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          summary TEXT NOT NULL,
          actor TEXT NOT NULL,
          source_app TEXT,
          location TEXT,
          occurred_at TEXT NOT NULL,
          metadata_json TEXT NOT NULL DEFAULT '{}',
          device_id TEXT NOT NULL
        );
        CREATE INDEX idx_activity_item_time ON activity(work_item_id, occurred_at);
        CREATE INDEX idx_activity_time ON activity(occurred_at);
        """

    /// The full v1 schema: 8 tables + 6 FTS sync triggers.
    ///
    /// The table DDL is the driver.md §6 schema verbatim. The six triggers keep the
    /// `search_index` FTS5 table populated as work items and attachments change —
    /// v1 search is `LIKE`-based (see `GRDBWorkItemRepository`), but the FTS table
    /// and its triggers are built now so attachment-name search (driver.md FR-15)
    /// has working infrastructure in a later increment.
    static let schemaV1 = """
        CREATE TABLE work_item (
          id TEXT PRIMARY KEY,               -- UUIDv7
          kind TEXT NOT NULL CHECK (kind IN ('epic','project','task','subtask')),
          parent_id TEXT REFERENCES work_item(id) ON DELETE SET NULL,
          title TEXT NOT NULL,
          description_md TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'todo',      -- todo|in_progress|done|cancelled
          priority INTEGER NOT NULL DEFAULT 3,      -- 1 urgent .. 4 low
          start_at TEXT, end_at TEXT,               -- ISO-8601 UTC
          completed_at TEXT,
          display_order TEXT NOT NULL,              -- fractional index, e.g. 'a0', 'a0V'
          color TEXT, tags_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
          version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL
        );
        CREATE INDEX idx_item_today ON work_item(deleted_at, status, end_at);
        CREATE INDEX idx_item_parent ON work_item(parent_id);

        CREATE TABLE action_item (           -- checklist inside a task
          id TEXT PRIMARY KEY, work_item_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
          text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order TEXT NOT NULL,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE attachment (
          id TEXT PRIMARY KEY, work_item_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
          type TEXT NOT NULL,          -- file|folder|email|calendar_event|teams_message|url|image|text
          uti TEXT,                    -- e.g. com.adobe.pdf, org.openxmlformats.spreadsheetml.sheet
          display_name TEXT NOT NULL,
          source_app TEXT,             -- outlook|mail|teams|finder|safari|...
          reference TEXT NOT NULL,     -- URL, deep link, message-id, or file path
          bookmark BLOB,               -- security-scoped bookmark for files/folders
          local_copy_path TEXT,        -- copied into app container when original is transient (.msg, .eml, images)
          metadata_json TEXT NOT NULL DEFAULT '{}',  -- sender, received date, page count, size...
          preview_text TEXT,           -- extracted text for search and AI
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1
        );

        CREATE TABLE item_link (
          id TEXT PRIMARY KEY,
          from_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
          to_id   TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
          type TEXT NOT NULL CHECK (type IN ('blocks','relates_to')),
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1,
          UNIQUE (from_id, to_id, type)
        );
        -- 'blocks' chain = one-way linked list: enforce at most one active outgoing and one incoming 'blocks' per item
        CREATE UNIQUE INDEX uq_blocks_out ON item_link(from_id) WHERE type='blocks' AND deleted_at IS NULL;
        CREATE UNIQUE INDEX uq_blocks_in  ON item_link(to_id)   WHERE type='blocks' AND deleted_at IS NULL;

        CREATE TABLE reminder (
          id TEXT PRIMARY KEY, work_item_id TEXT REFERENCES work_item(id) ON DELETE CASCADE,
          fire_at TEXT NOT NULL, kind TEXT NOT NULL,   -- task|end_of_day
          delivered_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
        );

        CREATE TABLE change_outbox (          -- feeds the future sync engine
          seq INTEGER PRIMARY KEY AUTOINCREMENT,
          entity TEXT NOT NULL, entity_id TEXT NOT NULL, op TEXT NOT NULL,  -- upsert|delete
          payload_json TEXT NOT NULL, created_at TEXT NOT NULL, synced_at TEXT
        );

        CREATE TABLE setting (key TEXT PRIMARY KEY, value_json TEXT NOT NULL);

        CREATE VIRTUAL TABLE search_index USING fts5(
          item_id UNINDEXED, title, description, attachments, tokenize='unicode61 remove_diacritics 2'
        );

        CREATE TRIGGER work_item_ai AFTER INSERT ON work_item BEGIN
            INSERT INTO search_index(item_id, title, description, attachments)
            VALUES (new.id, new.title, new.description_md, '');
        END;
        CREATE TRIGGER work_item_au AFTER UPDATE ON work_item BEGIN
            UPDATE search_index SET title = new.title, description = new.description_md
            WHERE item_id = new.id;
        END;
        CREATE TRIGGER work_item_ad AFTER DELETE ON work_item BEGIN
            DELETE FROM search_index WHERE item_id = old.id;
        END;
        CREATE TRIGGER attachment_ai AFTER INSERT ON attachment BEGIN
            UPDATE search_index SET attachments = (
                SELECT COALESCE(group_concat(display_name || ' ' || COALESCE(preview_text, ''), ' '), '')
                FROM attachment WHERE work_item_id = new.work_item_id
            ) WHERE item_id = new.work_item_id;
        END;
        CREATE TRIGGER attachment_au AFTER UPDATE ON attachment BEGIN
            UPDATE search_index SET attachments = (
                SELECT COALESCE(group_concat(display_name || ' ' || COALESCE(preview_text, ''), ' '), '')
                FROM attachment WHERE work_item_id = new.work_item_id
            ) WHERE item_id = new.work_item_id;
        END;
        CREATE TRIGGER attachment_ad AFTER DELETE ON attachment BEGIN
            UPDATE search_index SET attachments = (
                SELECT COALESCE(group_concat(display_name || ' ' || COALESCE(preview_text, ''), ' '), '')
                FROM attachment WHERE work_item_id = old.work_item_id
            ) WHERE item_id = old.work_item_id;
        END;
        """
}

/// Opens and configures a TodayFlow `DatabaseQueue`.
public enum TodayFlowDatabase {
    /// Opens the database at `url` (creating its parent directory if needed),
    /// applies all migrations, and returns the queue.
    ///
    /// - Enables the WAL journal mode (driver.md §6: "WAL" for concurrent reads).
    /// - Enables foreign keys (driver.md §6 sync-ready convention).
    public static func make(at url: URL) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try TodayFlowMigrations.current.migrate(queue)
        return queue
    }

    /// An in-memory database with all migrations applied (for tests).
    public static func makeInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try TodayFlowMigrations.current.migrate(queue)
        return queue
    }
}
