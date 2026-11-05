import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("GRDBWorkItemRepository")
struct GRDBWorkItemRepositoryTests {
    @Test("round-trips every field through the database")
    func roundTrips() async throws {
        let db = try TestDB.inMemory()
        let parent = WorkItem(kind: .project, title: "Parent")
        try await db.workItems.save(parent)
        let item = WorkItem(
            kind: .project,
            title: "Q1 planning",
            parentId: parent.id,
            descriptionMd: "Some **markdown**",
            summary: "Carol asks for the vendor totals by Friday.",
            status: .inProgress,
            priority: .urgent,
            startAt: Date.whole(year: 2026, month: 1, day: 5, hour: 9),
            endAt: Date.whole(year: 2026, month: 1, day: 5, hour: 17),
            completedAt: nil,
            displayOrder: "a0",
            color: "#FF0000",
            tags: ["work", "planning"],
            createdAt: Date.whole(year: 2026, month: 1, day: 5, hour: 8),
            updatedAt: Date.whole(year: 2026, month: 1, day: 5, hour: 8, minute: 30),
            deletedAt: nil,
            version: 3,
            deviceId: "device-1"
        )
        try await db.workItems.save(item)
        #expect(await db.workItems.item(item.id) == item)
    }

    @Test("save upserts by id")
    func saveUpsertsById() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "Once")
        try await db.workItems.save(item)
        var updated = item
        updated.title = "Twice"
        try await db.workItems.save(updated)

        let count = try await db.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM work_item")!
        }
        #expect(count == 1)
        #expect(await db.workItems.item(item.id)?.title == "Twice")
    }

    @Test("softDelete hides the item and appends an upsert outbox row")
    func softDelete() async throws {
        let db = try TestDB.inMemory()
        let item = WorkItem(title: "Doomed")
        try await db.workItems.save(item)
        try await db.workItems.softDelete(item.id, at: Date.whole(year: 2026, month: 1, day: 5, hour: 12))

        #expect(await db.workItems.item(item.id) == nil)
        let pending = try await db.outbox.pending()
        #expect(pending.count == 2)
        #expect(pending.allSatisfy { $0.op == "upsert" && $0.entityId == item.id.uuid.uuidString })
    }

    @Test("move reparents, reorders, and bumps the version")
    func move() async throws {
        let db = try TestDB.inMemory()
        let p1 = WorkItem(kind: .project, title: "P1")
        let p2 = WorkItem(kind: .project, title: "P2")
        let child = WorkItem(title: "Child", parentId: p1.id)
        try await db.workItems.save(p1)
        try await db.workItems.save(p2)
        try await db.workItems.save(child)

        try await db.workItems.move(
            child.id,
            toParent: p2.id,
            displayOrder: "z",
            at: Date.whole(year: 2026, month: 1, day: 5, hour: 12)
        )
        let moved = await db.workItems.item(child.id)
        #expect(moved?.parentId == p2.id)
        #expect(moved?.displayOrder == "z")
        #expect(moved?.version == 2)
    }

    @Test("todayItems partitions by start time, status, and deletion")
    func todayItemsPartitioning() async throws {
        let db = try TestDB.inMemory()
        let cal = WorkCalendar.standard
        let day = Date.whole(year: 2026, month: 1, day: 5)
        let dayStart = cal.calendar.startOfDay(for: day)

        // Local-time anchors so the test is correct in any time zone:
        // 10:00 and 18:00 are both today; tomorrow's 09:00 is not.
        let inItem = WorkItem(
            title: "In",
            startAt: dayStart.addingTimeInterval(10 * 3600),
            displayOrder: "a1"
        )
        let lateItem = WorkItem(
            title: "Late",
            startAt: dayStart.addingTimeInterval(18 * 3600),
            displayOrder: "a2"
        )
        let tomorrowItem = WorkItem(
            title: "Tomorrow",
            startAt: dayStart.addingTimeInterval(33 * 3600),
            displayOrder: "a3"
        )
        let doneItem = WorkItem(title: "Done", status: .done, startAt: dayStart.addingTimeInterval(10 * 3600))
        let deletedItem = WorkItem(
            title: "Deleted",
            startAt: dayStart.addingTimeInterval(10 * 3600),
            deletedAt: dayStart.addingTimeInterval(11 * 3600)
        )
        for item in [inItem, lateItem, tomorrowItem, doneItem, deletedItem] {
            try await db.workItems.save(item)
        }

        #expect(await db.workItems.todayItems(on: day, calendar: cal).map(\.title) == ["In", "Late"])
    }

    @Test("completedToday returns only items completed within the day")
    func completedToday() async throws {
        let db = try TestDB.inMemory()
        let cal = WorkCalendar.standard
        let day = Date.whole(year: 2026, month: 1, day: 5)
        let dayStart = cal.calendar.startOfDay(for: day)

        let done = WorkItem(
            title: "Done today",
            status: .done,
            completedAt: dayStart.addingTimeInterval(3600),
            updatedAt: dayStart.addingTimeInterval(3600)
        )
        let stale = WorkItem(
            title: "Done yesterday",
            status: .done,
            completedAt: dayStart.addingTimeInterval(-3600),
            updatedAt: dayStart.addingTimeInterval(-3600)
        )
        try await db.workItems.save(done)
        try await db.workItems.save(stale)

        #expect(await db.workItems.completedToday(on: day, calendar: cal).map(\.title) == ["Done today"])
    }

    @Test("children lists direct children in display order; nil lists top-level items")
    func children() async throws {
        let db = try TestDB.inMemory()
        let parent = WorkItem(kind: .project, title: "Parent", displayOrder: "a")
        let b = WorkItem(title: "B", parentId: parent.id, displayOrder: "a")
        let a = WorkItem(title: "A", parentId: parent.id, displayOrder: "b")
        let top = WorkItem(title: "Top", displayOrder: "b")
        try await db.workItems.save(parent)
        try await db.workItems.save(b)
        try await db.workItems.save(a)
        try await db.workItems.save(top)

        #expect(await db.workItems.children(of: parent.id).map(\.title) == ["B", "A"])
        #expect(await db.workItems.children(of: nil).map(\.title) == ["Parent", "Top"])
    }

    @Test("allItems returns every live item in display order, excluding soft-deleted")
    func allItems() async throws {
        let db = try TestDB.inMemory()
        let epic = WorkItem(kind: .epic, title: "Epic", displayOrder: "a")
        let task = WorkItem(title: "Task", parentId: epic.id, displayOrder: "b")
        let gone = WorkItem(
            title: "Gone",
            displayOrder: "c",
            deletedAt: Date.whole(year: 2026, month: 1, day: 5, hour: 12)
        )
        for item in [epic, task, gone] {
            try await db.workItems.save(item)
        }

        #expect(await db.workItems.allItems().map(\.title) == ["Epic", "Task"])
    }

    @Test("search matches title and description case-insensitively, with literal wildcards")
    func search() async throws {
        let db = try TestDB.inMemory()
        let report = WorkItem(title: "Alpha Report")
        let notes = WorkItem(title: "Notes", descriptionMd: "quarterly budget review")
        let percent = WorkItem(title: "100% Complete")
        let gone = WorkItem(
            title: "alpha gone",
            deletedAt: Date.whole(year: 2026, month: 1, day: 5, hour: 12)
        )
        for item in [report, notes, percent, gone] {
            try await db.workItems.save(item)
        }

        #expect(await db.workItems.search("alpha").map(\.title) == ["Alpha Report"])
        #expect(await db.workItems.search("ALPHA").map(\.title) == ["Alpha Report"])
        #expect(await db.workItems.search("budget").map(\.title) == ["Notes"])
        // The % must be treated literally, not as a LIKE wildcard.
        #expect(await db.workItems.search("100%").map(\.title) == ["100% Complete"])
        #expect(await db.workItems.search("").isEmpty)
    }

    @Test("observeToday emits the initial snapshot")
    func observeTodayInitialSnapshot() async throws {
        let db = try TestDB.inMemory()
        let cal = WorkCalendar.standard
        let day = Date.whole(year: 2026, month: 1, day: 5)
        let dayStart = cal.calendar.startOfDay(for: day)
        let item = WorkItem(title: "Visible", startAt: dayStart.addingTimeInterval(10 * 3600))
        try await db.workItems.save(item)

        let stream = await db.workItems.observeToday(on: day, calendar: cal)
        let snapshot = await stream.first { _ in true }
        #expect(snapshot?.map(\.title) == ["Visible"])
    }

    @Test("observeToday re-emits when rows change")
    func observeTodayReemits() async throws {
        let db = try TestDB.inMemory()
        let cal = WorkCalendar.standard
        let day = Date.whole(year: 2026, month: 1, day: 5)
        let dayStart = cal.calendar.startOfDay(for: day)
        let item = WorkItem(title: "Before", startAt: dayStart.addingTimeInterval(10 * 3600))
        try await db.workItems.save(item)

        let stream = await db.workItems.observeToday(on: day, calendar: cal)
        // `withThrowingTaskGroup` (not `withTaskGroup`) because the body throws.
        // `returning:` is explicit because the body returns `group.next()!`,
        // whose type is the group's own result generic — un-inferable on its own.
        let snapshots = try await withThrowingTaskGroup(
            of: [[WorkItem]].self,
            returning: [[WorkItem]].self
        ) { group in
            group.addTask {
                var collected: [[WorkItem]] = []
                for await snapshot in stream {
                    collected.append(snapshot)
                    if collected.count == 2 { break }
                }
                return collected
            }
            try await Task.sleep(for: .milliseconds(100))
            var updated = item
            updated.title = "After"
            try await db.workItems.save(updated)
            return try await group.next()!
        }
        #expect(snapshots.first?.first?.title == "Before")
        #expect(snapshots.last?.first?.title == "After")
    }
}
