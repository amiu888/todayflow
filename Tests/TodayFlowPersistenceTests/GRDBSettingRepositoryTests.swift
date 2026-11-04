import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("GRDBSettingRepository")
struct GRDBSettingRepositoryTests {
    @Test("sets and reads a value")
    func setAndRead() async throws {
        let db = try TestDB.inMemory()
        try await db.settings.set("{\"startHour\":9}", for: SettingKeys.workCalendar)
        #expect(await db.settings.value(for: SettingKeys.workCalendar) == "{\"startHour\":9}")
    }

    @Test("returns nil for an absent key")
    func absentKey() async throws {
        let db = try TestDB.inMemory()
        #expect(await db.settings.value(for: SettingKeys.aiEndpoint) == nil)
    }

    @Test("a second set replaces the value in place")
    func upsert() async throws {
        let db = try TestDB.inMemory()
        try await db.settings.set("one", for: "key")
        try await db.settings.set("two", for: "key")

        #expect(await db.settings.value(for: "key") == "two")
        let count = try await db.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM setting") ?? 0
        }
        #expect(count == 1)
    }

    @Test("keys are independent")
    func independentKeys() async throws {
        let db = try TestDB.inMemory()
        try await db.settings.set("a", for: "k1")
        try await db.settings.set("b", for: "k2")
        try await db.settings.set("a2", for: "k1")

        #expect(await db.settings.value(for: "k1") == "a2")
        #expect(await db.settings.value(for: "k2") == "b")
    }

    @Test("remove deletes the row and is idempotent")
    func remove() async throws {
        let db = try TestDB.inMemory()
        try await db.settings.set("a", for: "key")
        try await db.settings.remove("key")
        #expect(await db.settings.value(for: "key") == nil)
        try await db.settings.remove("key") // must not throw
    }

    @Test("values survive a reopen")
    func persistence() async throws {
        let (db, path) = try TestDB.file()
        defer {
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: path.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: path.appendingPathExtension("shm"))
        }
        try await db.settings.set("kept", for: "key")
        try db.queue.close()

        // Reopen: the value must be in the file, and migrations a no-op.
        let queue = try TodayFlowDatabase.make(at: path)
        defer { try? queue.close() }
        let settings = GRDBSettingRepository(queue: queue)
        #expect(await settings.value(for: "key") == "kept")
    }
}
