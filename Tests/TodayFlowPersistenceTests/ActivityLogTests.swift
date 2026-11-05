import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

private func activityDate(_ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(
        from: DateComponents(year: 2026, month: 11, day: 4, hour: hour)
    )!
}

private struct ActivityStack {
    let queue: DatabaseQueue
    let items: GRDBWorkItemRepository
    let links: GRDBLinkRepository
    let attachments: GRDBAttachmentRepository
    let activity: GRDBActivityRepository

    init() throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        self.queue = queue
        self.items = GRDBWorkItemRepository(queue: queue, actor: "tester")
        self.links = GRDBLinkRepository(queue: queue, actor: "tester")
        self.attachments = GRDBAttachmentRepository(queue: queue, actor: "tester")
        self.activity = GRDBActivityRepository(queue: queue)
    }
}

struct ActivityLogTests {
    @Test func save_recordsWhoCreatedTheItemAndWhen() async throws {
        let stack = try ActivityStack()
        let item = WorkItem(
            title: "Ship the release",
            startAt: activityDate(9),
            endAt: activityDate(17),
            updatedAt: activityDate(10)
        )
        try await stack.items.save(item)

        let events = await stack.activity.events(for: item.id)
        #expect(events.count == 1)
        #expect(events.first?.kind == .created)
        #expect(events.first?.summary == "Created “Ship the release”")
        #expect(events.first?.actor == "tester")
        #expect(events.first?.occurredAt == activityDate(10))
        #expect(events.first?.metadata["priority"] == "P3 Normal")
    }

    @Test func statusChange_recordsCompletedAndReopened() async throws {
        let stack = try ActivityStack()
        let item = WorkItem(title: "Ship", startAt: activityDate(9), endAt: activityDate(17))
        try await stack.items.save(item)

        try await SetStatus(repository: stack.items, deviceId: "test")
            .execute(item.id, to: .done, at: activityDate(15))
        try await SetStatus(repository: stack.items, deviceId: "test")
            .execute(item.id, to: .todo, at: activityDate(16))

        let events = await stack.activity.events(for: item.id)
        #expect(events.contains { $0.kind == .completed })
        #expect(events.contains { $0.kind == .reopened })
    }

    @Test func attachmentDrop_recordsSourceAppLocationAndTime() async throws {
        let stack = try ActivityStack()
        let item = WorkItem(title: "Screenshot task")
        try await stack.items.save(item)
        let attachment = Attachment(
            itemId: item.id,
            kind: .image,
            uti: "public.png",
            displayName: "shot.png",
            sourceApp: "com.apple.finder",
            reference: "/tmp/shot.png",
            metadata: ["origin": "drop"],
            createdAt: activityDate(11)
        )
        try await stack.attachments.save(attachment)

        let dropped = await stack.activity.events(for: item.id)
            .first { $0.kind == .dropped }
        #expect(dropped?.sourceApp == "com.apple.finder")
        #expect(dropped?.location == "/tmp/shot.png")
        #expect(dropped?.actor == "tester")
        #expect(dropped?.occurredAt == activityDate(11))
        #expect(dropped?.metadata["attachment_kind"] == "image")
        #expect(dropped?.metadata["uti"] == "public.png")
    }

    @Test func link_recordsAnEventOnBothItems() async throws {
        let stack = try ActivityStack()
        let prerequisite = WorkItem(title: "Approve")
        let dependent = WorkItem(title: "Publish")
        try await stack.items.save(prerequisite)
        try await stack.items.save(dependent)
        let link = ItemLink(
            fromId: prerequisite.id,
            toId: dependent.id,
            kind: .blocks,
            createdAt: activityDate(12)
        )
        try await stack.links.save(link)

        let fromEvents = await stack.activity.events(for: prerequisite.id)
            .filter { $0.kind == .linkAdded }
        let toEvents = await stack.activity.events(for: dependent.id)
            .filter { $0.kind == .linkAdded }

        #expect(fromEvents.first?.summary == "Now blocks “Publish”")
        #expect(toEvents.first?.summary == "Blocked by “Approve”")
        #expect(fromEvents.first?.occurredAt == activityDate(12))
    }

    @Test func recent_returnsNewestFirstAcrossItems() async throws {
        let stack = try ActivityStack()
        let first = WorkItem(title: "First")
        let second = WorkItem(title: "Second")
        try await stack.items.save(first)
        try await stack.items.save(second)

        let events = await stack.activity.recent(limit: 10)
        #expect(events.count == 2)
        #expect(events.map(\.itemId) == [second.id, first.id])
    }
}
