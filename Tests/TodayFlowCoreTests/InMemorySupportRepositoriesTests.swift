import Foundation
import Testing
@testable import TodayFlowCore

struct InMemoryLinkRepositoryTests {
    @Test func linksFromAndTo() async {
        let repo = InMemoryLinkRepository()
        let a = UUIDv7.new()
        let b = UUIDv7.new()
        let c = UUIDv7.new()
        let l1 = ItemLink(fromId: a, toId: b)
        let l2 = ItemLink(fromId: b, toId: c)
        await repo.seed(l1)
        await repo.seed(l2)

        #expect(await repo.links(from: b) == [l2])
        #expect(await repo.links(to: b) == [l1])
        #expect((await repo.allLinks()).count == 2)
    }

    @Test func deleteRemoves() async throws {
        let repo = InMemoryLinkRepository()
        let link = ItemLink(fromId: UUIDv7.new(), toId: UUIDv7.new())
        await repo.seed(link)
        try await repo.delete(link.id)
        #expect((await repo.allLinks()).isEmpty)
    }
}

struct InMemoryAttachmentRepositoryTests {
    @Test func attachmentsForItem() async {
        let repo = InMemoryAttachmentRepository()
        let item = UUIDv7.new()
        let att = Attachment(itemId: item, kind: .file, displayName: "x.pdf")
        await repo.seed(att)
        await repo.seed(Attachment(itemId: UUIDv7.new(), kind: .file, displayName: "y.pdf"))

        #expect(await repo.attachments(for: item) == [att])
    }

    @Test func deleteRemoves() async throws {
        let repo = InMemoryAttachmentRepository()
        let att = Attachment(itemId: UUIDv7.new(), kind: .file, displayName: "x.pdf")
        await repo.seed(att)
        try await repo.delete(att.id)
        #expect(await repo.all.isEmpty)
    }
}
