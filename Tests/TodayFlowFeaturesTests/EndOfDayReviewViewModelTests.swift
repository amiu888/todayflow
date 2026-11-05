import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private let reviewCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let reviewWork = WorkCalendar(
    startHour: 9,
    endHour: 17,
    workWeekdays: [2, 3, 4, 5, 6],
    calendar: reviewCalendar
)

/// Wednesday 2026-11-04, 17:30 UTC — just after end of business.
private let reviewNow = reviewCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 4, hour: 17, minute: 30)
)!

private func reviewDate(
    _ month: Int, _ day: Int, hour: Int = 0
) -> Date {
    reviewCalendar.date(
        from: DateComponents(year: 2026, month: month, day: day, hour: hour)
    )!
}

private func reviewTask(
    _ title: String,
    status: Status = .todo,
    endAt: Date = reviewDate(11, 4, hour: 17),
    displayOrder: String = "a1"
) -> WorkItem {
    WorkItem(
        title: title,
        status: status,
        startAt: reviewDate(11, 4, hour: 9),
        endAt: endAt,
        displayOrder: displayOrder
    )
}

@MainActor
private final class FinishLog {
    private(set) var count = 0
    func record() { count += 1 }
}

@MainActor
private struct ReviewFixture {
    let repository = InMemoryWorkItemRepository()
    let links = InMemoryLinkRepository()
    let log = FinishLog()

    func model() -> EndOfDayReviewViewModel {
        EndOfDayReviewViewModel(
            repository: repository,
            linkRepository: links,
            calendar: reviewWork,
            clock: { reviewNow },
            onFinished: { [log] in log.record() }
        )
    }
}

struct EndOfDayReviewViewModelTests {
    @Test @MainActor
    func load_listsOpenTasksAndSkipsCompletedOnes() async {
        let f = ReviewFixture()
        await f.repository.seed(reviewTask("Open"))
        await f.repository.seed(reviewTask("Done", status: .done, displayOrder: "a2"))
        await f.repository.seed(reviewTask("Cancelled", status: .cancelled, displayOrder: "a3"))
        let model = f.model()

        await model.load()

        #expect(model.rows.map(\.title) == ["Open"])
        #expect(f.log.count == 0)
    }

    @Test @MainActor
    func load_withNoOpenTasksFinishesImmediately() async {
        let f = ReviewFixture()
        await f.repository.seed(reviewTask("Done", status: .done))
        let model = f.model()

        await model.load()

        #expect(model.rows.isEmpty)
        #expect(f.log.count == 1)
    }

    @Test @MainActor
    func moveToTomorrow_movesToNextWorkingDayAndRemovesRow() async {
        let f = ReviewFixture()
        let task = reviewTask("Open")
        await f.repository.seed(task)
        let model = f.model()
        await model.load()

        await model.moveToTomorrow(task.id)

        #expect(model.rows.isEmpty)
        #expect(await f.repository.item(task.id)?.endAt == reviewDate(11, 5, hour: 17))
        #expect(f.log.count == 1)
    }

    @Test @MainActor
    func markDone_completesTaskAndRemovesRow() async {
        let f = ReviewFixture()
        let task = reviewTask("Open")
        await f.repository.seed(task)
        let model = f.model()
        await model.load()

        await model.markDone(task.id)

        #expect(model.rows.isEmpty)
        let updated = await f.repository.item(task.id)
        #expect(updated?.status == .done)
        #expect(updated?.completedAt == reviewNow)
        #expect(f.log.count == 1)
    }

    @Test @MainActor
    func moveToPickedDateUsesThatDaysEndOfBusiness() async {
        let f = ReviewFixture()
        let task = reviewTask("Open")
        await f.repository.seed(task)
        let model = f.model()
        await model.load()

        await model.move(task.id, to: reviewDate(11, 10))

        #expect(model.rows.isEmpty)
        #expect(await f.repository.item(task.id)?.endAt == reviewDate(11, 10, hour: 17))
    }

    @Test @MainActor
    func keep_leavesTaskUntouchedAndFinishesWhenLastRowGoes() async {
        let f = ReviewFixture()
        let task = reviewTask("Open")
        await f.repository.seed(task)
        let model = f.model()
        await model.load()

        model.keep(task.id)

        #expect(model.rows.isEmpty)
        #expect(await f.repository.item(task.id)?.endAt == task.endAt)
        #expect(f.log.count == 1)
    }

    @Test @MainActor
    func finish_isIdempotent() async {
        let f = ReviewFixture()
        let model = f.model()

        model.finish()
        model.finish()

        #expect(f.log.count == 1)
    }

    @Test @MainActor
    func load_surfacesErrorFromBlockedCompletion() async throws {
        let f = ReviewFixture()
        let blocker = reviewTask("Blocker", displayOrder: "a1")
        let blocked = reviewTask("Blocked", displayOrder: "a2")
        await f.repository.seed(blocker)
        await f.repository.seed(blocked)
        try await f.links.save(
            ItemLink(fromId: blocker.id, toId: blocked.id, kind: .blocks)
        )
        let model = f.model()
        await model.load()

        await model.markDone(blocked.id)

        #expect(model.lastError != nil)
        #expect(model.rows.contains { $0.id == blocked.id })
    }
}
