import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("GRDBLinkRepository")
struct GRDBLinkRepositoryTests {
    @Test("saves and reads links by direction")
    func saveAndRead() async throws {
        let db = try TestDB.inMemory()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        let c = WorkItem(title: "C")
        for item in [a, b, c] {
            try await db.workItems.save(item)
        }

        // A valid blocks chain: a -> b -> c (one outgoing, one incoming each).
        let ab = ItemLink(fromId: a.id, toId: b.id, kind: .blocks)
        let bc = ItemLink(fromId: b.id, toId: c.id, kind: .blocks)
        try await db.links.save(ab)
        try await db.links.save(bc)

        #expect(await db.links.links(from: a.id).map(\.id) == [ab.id])
        #expect(await db.links.links(to: b.id).map(\.id) == [ab.id])
        #expect(await db.links.allLinks().count == 2)
    }

    @Test("a second active outgoing blocks link throws")
    func duplicateOutgoingBlocksThrows() async throws {
        let db = try TestDB.inMemory()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        let c = WorkItem(title: "C")
        for item in [a, b, c] {
            try await db.workItems.save(item)
        }
        try await db.links.save(ItemLink(fromId: a.id, toId: b.id, kind: .blocks))
        await #expect(throws: (any Error).self) {
            try await db.links.save(ItemLink(fromId: a.id, toId: c.id, kind: .blocks))
        }
    }

    @Test("a duplicate (from, to, type) link throws")
    func duplicateLinkThrows() async throws {
        let db = try TestDB.inMemory()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        try await db.workItems.save(a)
        try await db.workItems.save(b)
        try await db.links.save(ItemLink(fromId: a.id, toId: b.id, kind: .blocks))
        await #expect(throws: (any Error).self) {
            try await db.links.save(ItemLink(fromId: a.id, toId: b.id, kind: .blocks))
        }
    }

    @Test("delete removes the row and appends a delete outbox row")
    func delete() async throws {
        let db = try TestDB.inMemory()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        try await db.workItems.save(a)
        try await db.workItems.save(b)
        let link = ItemLink(fromId: a.id, toId: b.id)
        try await db.links.save(link)

        #expect(await db.links.allLinks().count == 1)
        try await db.links.delete(link.id)
        #expect(await db.links.allLinks().isEmpty)
        #expect(await db.links.links(from: a.id).isEmpty)

        let pending = try await db.outbox.pending()
        #expect(pending.last?.op == "delete")
        #expect(pending.last?.entityId == link.id.uuid.uuidString)
    }
}
