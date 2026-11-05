import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence
import TodayFlowSync

struct NoopSyncEngineTests {
    @Test func pushAndPull_areNoOps() async throws {
        let engine = NoopSyncEngine()
        try await engine.pushPending()
        try await engine.pull()
    }

    @Test func push_leavesTheOutboxPendingForV2() async throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        let items = GRDBWorkItemRepository(queue: queue)
        let outbox = OutboxStore(queue: queue)

        try await items.save(WorkItem(title: "Offline change"))
        let before = try await outbox.pending()
        #expect(!before.isEmpty)

        let engine = NoopSyncEngine(outbox: outbox)
        try await engine.pushPending()
        try await engine.pull()

        let after = try await outbox.pending()
        #expect(after.count == before.count)
        #expect(after.allSatisfy { $0.syncedAt == nil })
    }
}
