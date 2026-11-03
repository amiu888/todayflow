import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("GRDBAttachmentRepository")
struct GRDBAttachmentRepositoryTests {
    @Test("round-trips every field through the database")
    func roundTrips() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "Spec task")
        try await db.workItems.save(item)
        let attachment = Attachment(
            itemId: item.id,
            kind: .file,
            uti: "com.adobe.pdf",
            displayName: "Spec.pdf",
            sourceApp: "Safari",
            reference: "file:///tmp/Spec.pdf",
            bookmark: Data([1, 2, 3]),
            localCopyPath: "/tmp/copy.pdf",
            metadata: ["pages": "42"],
            previewText: "the spec",
            createdAt: Date.whole(year: 2026, month: 1, day: 5, hour: 10)
        )
        try await db.attachments.save(attachment)
        #expect(await db.attachments.attachments(for: item.id) == [attachment])
    }

    @Test("a nil reference is stored as empty text and reads back as nil")
    func nilReference() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "T")
        try await db.workItems.save(item)
        let attachment = Attachment(itemId: item.id, kind: .url, displayName: "Link")
        try await db.attachments.save(attachment)
        #expect(await db.attachments.attachments(for: item.id).first?.reference == nil)
    }

    @Test("delete removes the row and appends a delete outbox row")
    func delete() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "T")
        try await db.workItems.save(item)
        let attachment = Attachment(itemId: item.id, kind: .file, displayName: "Gone.pdf")
        try await db.attachments.save(attachment)

        #expect(await db.attachments.attachments(for: item.id).count == 1)
        try await db.attachments.delete(attachment.id)
        #expect(await db.attachments.attachments(for: item.id).isEmpty)

        let pending = try await db.outbox.pending()
        #expect(pending.last?.op == "delete")
        #expect(pending.last?.entityId == attachment.id.uuid.uuidString)
    }

    @Test("FTS triggers keep search_index in sync")
    func ftsTriggers() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "Spec task")
        try await db.workItems.save(item)
        let idString = item.id.uuid.uuidString

        // The work_item_ai trigger inserted the row with an empty attachments column.
        let before = try await db.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT attachments FROM search_index WHERE item_id = ?",
                arguments: [idString]
            )
        }
        #expect(before == "")

        let attachment = Attachment(
            itemId: item.id, kind: .file, displayName: "Spec.pdf", previewText: "the spec"
        )
        try await db.attachments.save(attachment)

        // The attachment_ai trigger rebuilt the column via group_concat.
        let after = try await db.queue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT attachments FROM search_index WHERE item_id = ?",
                arguments: [idString]
            )
        }
        #expect(after == "Spec.pdf the spec")
    }
}
