import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("Migrations")
struct MigrationsTests {
    @Test("v1 creates all 8 schema objects and 6 FTS triggers")
    func createsAllObjects() throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        defer { try? queue.close() }

        let tables = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
                .map { $0["name"] as String }
                .sorted()
        }
        // 7 real tables + the FTS5 virtual table (search_index)
        #expect(tables.contains("work_item"))
        #expect(tables.contains("action_item"))
        #expect(tables.contains("attachment"))
        #expect(tables.contains("item_link"))
        #expect(tables.contains("reminder"))
        #expect(tables.contains("change_outbox"))
        #expect(tables.contains("setting"))
        #expect(tables.contains("activity"))
        #expect(tables.contains("search_index"))

        let triggers = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'trigger'")
                .map { $0["name"] as String }
                .sorted()
        }
        #expect(triggers == [
            "attachment_ad", "attachment_ai", "attachment_au",
            "work_item_ad", "work_item_ai", "work_item_au",
        ])
    }

    @Test("a file database persists across close and reopen, and re-migrates idempotently")
    func filePersistsAndReopens() async throws {
        let path = URL.temporaryDirectory
            .appendingPathComponent("todayflow-migration-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: path.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: path.appendingPathExtension("shm"))
        }

        do {
            let queue = try TodayFlowDatabase.make(at: path)
            let item = WorkItem(title: "Survives restart")
            try await queue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO work_item (
                          id, kind, title, status, priority, display_order,
                          created_at, updated_at, version, device_id
                        ) VALUES (?, 'task', ?, 'todo', 3, 'a', ?, ?, 1, 'local')
                        """,
                    arguments: [
                        item.id.uuid.uuidString,
                        item.title,
                        SqlTimestamp.encode(item.createdAt),
                        SqlTimestamp.encode(item.updatedAt),
                    ]
                )
            }
            try queue.close()
        }

        // Reopen: migrations must be a no-op, and the row must be there.
        let queue = try TodayFlowDatabase.make(at: path)
        defer { try? queue.close() }
        let count = try await queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM work_item")!
        }
        #expect(count == 1)
    }
}

@Test func v5AddsSummaryWithAnEmptyDefault() throws {
    let queue = try TodayFlowDatabase.makeInMemory()
    defer { try? queue.close() }

    let columns = try queue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(work_item)")
            .map { $0["name"] as String }
    }
    #expect(columns.contains("summary"))

    try queue.write { db in
        try db.execute(
            sql: """
                INSERT INTO work_item (
                  id, kind, title, status, priority, display_order,
                  created_at, updated_at, version, device_id
                ) VALUES (?, 'task', 'No summary', 'todo', 3, 'a', ?, ?, 1, 'local')
                """,
            arguments: [
                UUIDv7.new().uuid.uuidString,
                SqlTimestamp.encode(Date()),
                SqlTimestamp.encode(Date()),
            ]
        )
    }
    let summary = try queue.read { db in
        try String.fetchOne(db, sql: "SELECT summary FROM work_item LIMIT 1")
    }
    #expect(summary == "")
}

@Test func v6AddsContactsGroupsAndTaskLinks() throws {
    let queue = try TodayFlowDatabase.makeInMemory()
    defer { try? queue.close() }
    let tables = try queue.read { db in
        try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
    }
    #expect(tables.contains("contact"))
    #expect(tables.contains("contact_group"))
    #expect(tables.contains("contact_group_member"))
    #expect(tables.contains("task_contact"))
}

@Test func v7AddsTwoLevelContactGroups() throws {
    let queue = try TodayFlowDatabase.makeInMemory()
    defer { try? queue.close() }

    let columns = try queue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA table_info(contact_group)")
            .map { $0["name"] as String }
    }
    #expect(columns.contains("parent_id"))

    let indexes = try queue.read { db in
        try String.fetchAll(
            db,
            sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
        )
    }
    #expect(indexes.contains("idx_contact_group_parent"))
}
