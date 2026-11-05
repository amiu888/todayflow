import Foundation
import Testing
@testable import TodayFlowCore

struct InMemoryWorkItemRepositoryTests {
    @Test func todayItemsIncludesAfterHoursStartsButNotTomorrow() async {
        let repo = InMemoryWorkItemRepository()
        let cal = TestDates.workCalendar
        let day = TestDates.monday
        let included = WorkItem(
            title: "In",
            startAt: TestDates.date(2026, 1, 5, hour: 10),
            displayOrder: "a1"
        )
        // 18:30 is after EOB but still today. An after-hours capture must be
        // visible in Today, not silently disappear into tomorrow.
        let late = WorkItem(
            title: "Late",
            startAt: TestDates.date(2026, 1, 5, hour: 18, minute: 30),
            displayOrder: "a2"
        )
        let tomorrow = WorkItem(
            title: "Tomorrow",
            startAt: TestDates.date(2026, 1, 6, hour: 9),
            displayOrder: "a3"
        )
        let done = WorkItem(title: "Done", status: .done, startAt: TestDates.date(2026, 1, 5, hour: 10))
        let deleted = WorkItem(
            title: "Del",
            startAt: TestDates.date(2026, 1, 5, hour: 10),
            deletedAt: TestDates.date(2026, 1, 5, hour: 12)
        )
        await repo.seed(included)
        await repo.seed(late)
        await repo.seed(tomorrow)
        await repo.seed(done)
        await repo.seed(deleted)

        let result = await repo.todayItems(on: day, calendar: cal)
        #expect(result.map(\.title) == ["In", "Late"])
    }

    @Test func itemReturnsNilForSoftDeleted() async throws {
        let repo = InMemoryWorkItemRepository()
        let item = WorkItem(title: "X")
        await repo.seed(item)
        #expect(await repo.item(item.id) != nil)
        try await repo.softDelete(item.id, at: .now)
        #expect(await repo.item(item.id) == nil)
    }

    @Test func childrenFiltersByParent() async {
        let repo = InMemoryWorkItemRepository()
        let project = WorkItem(kind: .project, title: "P")
        let task = WorkItem(kind: .task, title: "T", parentId: project.id)
        let standalone = WorkItem(kind: .task, title: "S")
        await repo.seed(project)
        await repo.seed(task)
        await repo.seed(standalone)

        let children = await repo.children(of: project.id)
        #expect(children.map(\.title) == ["T"])
        let top = await repo.children(of: nil)
        #expect(Set(top.map(\.title)) == Set(["P", "S"]))
    }

    @Test func moveUpdatesParentAndOrder() async throws {
        let repo = InMemoryWorkItemRepository()
        let item = WorkItem(title: "X", displayOrder: "1")
        await repo.seed(item)
        let newParent = WorkItem(kind: .project, title: "P")
        await repo.seed(newParent)

        try await repo.move(item.id, toParent: newParent.id, displayOrder: "5", at: .now)

        let updated = await repo.item(item.id)
        #expect(updated?.parentId == newParent.id)
        #expect(updated?.displayOrder == "5")
    }

    @Test func searchMatchesTitleCaseInsensitive() async {
        let repo = InMemoryWorkItemRepository()
        await repo.seed(WorkItem(title: "Write report"))
        await repo.seed(WorkItem(title: "Review code"))
        let results = await repo.search("REPORT")
        #expect(results.map(\.title) == ["Write report"])
    }

    @Test func observeTodayYieldsInitial() async {
        let repo = InMemoryWorkItemRepository()
        let cal = TestDates.workCalendar
        let item = WorkItem(title: "In", startAt: TestDates.date(2026, 1, 5, hour: 10))
        await repo.seed(item)

        let stream = await repo.observeToday(on: TestDates.monday, calendar: cal)
        let first = await stream.first { _ in true } // initial snapshot
        #expect(first?.map(\.title) == ["In"])
    }
}
