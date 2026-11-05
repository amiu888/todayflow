import Foundation
import Testing
import TodayFlowCore
import TodayFlowMac

private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@MainActor
private struct Fixture {
    let repository = InMemoryWorkItemRepository()
    let calendar = WorkCalendar(
        startHour: 9,
        endHour: 17,
        workWeekdays: [2, 3, 4, 5, 6],
        calendar: testCalendar
    )
    /// 2026-11-04 is a Wednesday (weekday 4) — a workday.
    let now = testCalendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!
    let model: TodaySummaryModel

    init() {
        // Bind before the closure: a `@Sendable` closure cannot capture the
        // struct's `inout self`, only Sendable values.
        let now = self.now
        model = TodaySummaryModel(repository: repository, calendar: calendar, clock: { now })
    }

    /// A on-time open task (9:00–11:00).
    func openOnTime() -> WorkItem {
        WorkItem(
            title: "On time task",
            status: .todo,
            startAt: testCalendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
            endAt: testCalendar.date(bySettingHour: 11, minute: 0, second: 0, of: now)!,
            displayOrder: "a1"
        )
    }

    /// An overdue open task (8:00–9:30, past due at 10:00).
    func openOverdue() -> WorkItem {
        WorkItem(
            title: "Overdue task",
            status: .inProgress,
            startAt: testCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: now)!,
            endAt: testCalendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
            displayOrder: "a2"
        )
    }

    /// A task completed at 9:45 today.
    func doneToday() -> WorkItem {
        WorkItem(
            title: "Done task",
            status: .done,
            startAt: testCalendar.date(bySettingHour: 8, minute: 0, second: 0, of: now)!,
            endAt: testCalendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!,
            completedAt: testCalendar.date(bySettingHour: 9, minute: 45, second: 0, of: now),
            displayOrder: "a3"
        )
    }
}

struct TodaySummaryModelTests {
    @Test @MainActor
    func refresh_computesProgress() async {
        let f = Fixture()
        await f.repository.seed(f.openOnTime())
        await f.repository.seed(f.openOverdue())
        await f.repository.seed(f.doneToday())
        await f.model.refresh()

        let progress = f.model.progress
        #expect(progress.done == 1)
        #expect(progress.total == 3)
        #expect(progress.remaining == 2)
        #expect(progress.overdue == 1)
        #expect(abs(progress.fraction - 1.0 / 3.0) < 0.001)
        // 10:00 → 17:00 end of business.
        #expect(progress.secondsUntilEOB == 25200)
        #expect(!progress.isCleared)
        // The overdue item sorts first in display order.
        #expect(f.model.nextTitle == "Overdue task")
    }

    @Test @MainActor
    func refresh_emptyRepository_reportsZeros() async {
        let f = Fixture()
        await f.model.refresh()

        let progress = f.model.progress
        #expect(progress.done == 0)
        #expect(progress.total == 0)
        #expect(progress.remaining == 0)
        #expect(progress.overdue == 0)
        #expect(progress.fraction == 0)
        #expect(!progress.isCleared, "an empty day is not a cleared day")
        #expect(f.model.nextTitle == nil)
    }

    @Test @MainActor
    func refresh_clearedDay() async {
        let f = Fixture()
        await f.repository.seed(f.doneToday())
        await f.model.refresh()

        #expect(f.model.progress.isCleared)
        #expect(f.model.progress.fraction == 1)
        #expect(f.model.nextTitle == nil)
    }

    @Test @MainActor
    func onRefreshedFiresWithNewProgress() async {
        let f = Fixture()
        await f.repository.seed(f.openOnTime())
        var received: [Int] = []
        f.model.onRefreshed = { received.append($0.remaining) }
        await f.model.refresh()
        #expect(received == [1])
    }

    @Test @MainActor
    func updateCalendarChangesEOB() async {
        let f = Fixture()
        await f.model.refresh()
        let before = f.model.progress.secondsUntilEOB

        var shorter = f.calendar
        shorter.endHour = 12
        f.model.updateCalendar(shorter)
        await f.model.refresh()

        // 10:00 → 12:00 is 7200 s, down from 25200 s.
        #expect(f.model.progress.secondsUntilEOB == 7200)
        #expect(f.model.progress.secondsUntilEOB < before)
    }

    @Test @MainActor
    func startPollingRefreshesRepeatedly() async throws {
        let f = Fixture()
        var refreshCount = 0
        f.model.onRefreshed = { _ in refreshCount += 1 }
        f.model.startPolling(every: 0.05)
        // Wait for the condition with a deadline instead of a fixed sleep:
        // under full-suite load (the Keychain tests hammer the system
        // Keychain in the same process) a fixed window can starve the
        // polling task and flake.
        let deadline = ContinuousClock.now + .seconds(5)
        while refreshCount < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        f.model.stopPolling()
        #expect(refreshCount >= 2)
    }
}

// MARK: - End-of-day review trigger (FR-43)

@MainActor
private func summaryModel(
    at hour: Int,
    minute: Int = 0,
    tasks: [WorkItem]
) async -> (TodaySummaryModel, InMemoryWorkItemRepository) {
    let repository = InMemoryWorkItemRepository()
    for task in tasks { await repository.seed(task) }
    let calendar = WorkCalendar(
        startHour: 9,
        endHour: 17,
        workWeekdays: [2, 3, 4, 5, 6],
        calendar: testCalendar
    )
    let now = testCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute)
    )!
    return (
        TodaySummaryModel(repository: repository, calendar: calendar, clock: { now }),
        repository
    )
}

private func summaryTask(_ title: String, status: Status = .todo) -> WorkItem {
    WorkItem(
        title: title,
        status: status,
        startAt: testCalendar.date(
            from: DateComponents(year: 2026, month: 11, day: 4, hour: 9)
        )!,
        endAt: testCalendar.date(
            from: DateComponents(year: 2026, month: 11, day: 4, hour: 17)
        )!,
        displayOrder: "a1"
    )
}

@Test @MainActor
func endOfDayReview_firesOnceAfterBusinessWithOpenTasks() async {
    let (model, _) = await summaryModel(at: 17, minute: 30, tasks: [summaryTask("Open")])
    var count = 0
    model.onEndOfDay = { count += 1 }

    await model.refresh()
    await model.refresh()

    #expect(count == 1)
}

@Test @MainActor
func endOfDayReview_doesNotFireBeforeBusinessEnds() async {
    let (model, _) = await summaryModel(at: 16, minute: 30, tasks: [summaryTask("Open")])
    var count = 0
    model.onEndOfDay = { count += 1 }

    await model.refresh()

    #expect(count == 0)
}

@Test @MainActor
func endOfDayReview_doesNotFireWhenDayIsCleared() async {
    let (model, _) = await summaryModel(
        at: 17,
        minute: 30,
        tasks: [summaryTask("Done", status: .done)]
    )
    var count = 0
    model.onEndOfDay = { count += 1 }

    await model.refresh()

    #expect(count == 0)
}
