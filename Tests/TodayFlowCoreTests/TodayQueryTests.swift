import Foundation
import Testing
@testable import TodayFlowCore

struct TodayQueryTests {
    private func makeUseCase() -> (TodayQuery, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        let uc = TodayQuery(repository: repo, calendar: TestDates.workCalendar)
        return (uc, repo)
    }

    @Test func partitionsOverdueAndOpen() async {
        let (uc, repo) = makeUseCase()
        let day = TestDates.monday
        let now = TestDates.date(2026, 1, 5, hour: 15)
        let overdue = WorkItem(
            title: "Overdue",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 10),
            displayOrder: "1"
        )
        let onTime = WorkItem(
            title: "OnTime",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            displayOrder: "2"
        )
        await repo.seed(overdue)
        await repo.seed(onTime)

        let result = await uc.execute(on: day, at: now)
        #expect(result.overdue.map(\.title) == ["Overdue"])
        #expect(result.open.map(\.title) == ["OnTime"])
        #expect(result.progress.overdue == 1)
    }

    @Test func projectsAndEpicsAreNotDayTasks() async {
        let (uc, repo) = makeUseCase()
        let day = TestDates.monday
        let now = TestDates.date(2026, 1, 5, hour: 15)
        let project = WorkItem(
            kind: .project,
            title: "Website",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            displayOrder: "1"
        )
        let epic = WorkItem(
            kind: .epic,
            title: "Q1",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            displayOrder: "2"
        )
        let task = WorkItem(
            title: "Ship it",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            displayOrder: "3"
        )
        await repo.seed(project)
        await repo.seed(epic)
        await repo.seed(task)

        let result = await uc.execute(on: day, at: now)

        #expect(result.open.map(\.title) == ["Ship it"])
        #expect(result.progress.total == 1)
    }

    @Test func doneTodaySectionAndProgress() async {
        let (uc, repo) = makeUseCase()
        let day = TestDates.monday
        let now = TestDates.date(2026, 1, 5, hour: 15)
        let open = WorkItem(
            title: "Open",
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            displayOrder: "1"
        )
        let done = WorkItem(
            title: "Done",
            status: .done,
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            completedAt: TestDates.date(2026, 1, 5, hour: 11),
            displayOrder: "2"
        )
        await repo.seed(open)
        await repo.seed(done)

        let result = await uc.execute(on: day, at: now)
        #expect(result.doneToday.map(\.title) == ["Done"])
        #expect(result.progress.done == 1)
        #expect(result.progress.total == 2)
        #expect(result.progress.remaining == 1)
        #expect(result.progress.fraction == 0.5)
        #expect(!result.progress.isCleared)
    }

    @Test func dayClearedWhenNoOpen() async {
        // Acceptance: complete the last task → ring at 100%, "Day cleared".
        let (uc, repo) = makeUseCase()
        let day = TestDates.monday
        let now = TestDates.date(2026, 1, 5, hour: 15)
        let done = WorkItem(
            title: "Done",
            status: .done,
            startAt: TestDates.date(2026, 1, 5, hour: 9),
            endAt: TestDates.date(2026, 1, 5, hour: 17),
            completedAt: TestDates.date(2026, 1, 5, hour: 11)
        )
        await repo.seed(done)

        let result = await uc.execute(on: day, at: now)
        #expect(result.open.isEmpty)
        #expect(result.progress.remaining == 0)
        #expect(result.progress.isCleared)
        #expect(result.progress.fraction == 1.0)
    }

    @Test func emptyDay() async {
        let (uc, _) = makeUseCase()
        let result = await uc.execute(on: TestDates.monday, at: TestDates.date(2026, 1, 5, hour: 15))
        #expect(result.progress.total == 0)
        #expect(result.progress.fraction == 0)
        #expect(!result.progress.isCleared)
    }
}
