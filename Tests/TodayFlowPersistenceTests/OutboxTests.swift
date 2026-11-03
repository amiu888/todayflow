import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("Outbox")
struct OutboxTests {
    @Test("save appends an upsert row with a decodable payload")
    func saveAppendsOutboxRow() async throws {
        let db = try TestDB.inMemory()
        // Every date must be whole-second: the payload round-trips through
        // `SqlTimestamp` (millisecond precision), so the memberwise-default
        // `.now` (sub-millisecond) would not survive the round-trip equal.
        let item = WorkItem(
            title: "Outbox check",
            startAt: Date.whole(year: 2026, month: 1, day: 5, hour: 8),
            endAt: Date.whole(year: 2026, month: 1, day: 5, hour: 17),
            createdAt: Date.whole(year: 2026, month: 1, day: 5, hour: 8),
            updatedAt: Date.whole(year: 2026, month: 1, day: 5, hour: 9)
        )
        try await db.workItems.save(item)

        let pending = try await db.outbox.pending()
        #expect(pending.count == 1)
        let row = try #require(pending.first)
        #expect(row.entity == "work_item")
        #expect(row.entityId == item.id.uuid.uuidString)
        #expect(row.op == "upsert")
        #expect(row.createdAt == Date.whole(year: 2026, month: 1, day: 5, hour: 9))
        #expect(row.syncedAt == nil)
        #expect(try Json.decode(WorkItem.self, from: row.payloadJson) == item)
    }

    @Test("markSynced removes rows from pending")
    func markSynced() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "Sync me")
        try await db.workItems.save(item)
        let pending = try await db.outbox.pending()
        #expect(pending.count == 1)
        try await db.outbox.markSynced([try #require(pending.first).seq], at: .now)
        #expect(try await db.outbox.pending().isEmpty)
    }
}
