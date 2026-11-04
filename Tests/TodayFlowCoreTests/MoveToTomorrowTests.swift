import Foundation
import Testing
@testable import TodayFlowCore

struct MoveToTomorrowTests {
    private let calendar = TestDates.workCalendar

    private func makeUseCase() -> (MoveToTomorrow, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        return (MoveToTomorrow(repository: repo, calendar: calendar), repo)
    }

    @Test func midWeekMoveLandsOnNextDayEOB() async throws {
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task")
        await repo.seed(item)

        // Monday 12:00 → Tuesday 17:00.
        let moved = try await uc.execute(item.id, at: TestDates.date(2026, 1, 5, hour: 12))
        #expect(moved.endAt == TestDates.date(2026, 1, 6, hour: 17))
        #expect(moved.startAt == item.startAt) // untouched
        #expect(moved.version == 2)
    }

    @Test func fridayMoveSkipsTheWeekend() async throws {
        // Acceptance-adjacent: "tomorrow" means the next *working* day.
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task")
        await repo.seed(item)

        // Friday 12:00 → Monday 17:00.
        let moved = try await uc.execute(item.id, at: TestDates.date(2026, 1, 9, hour: 12))
        #expect(moved.endAt == TestDates.date(2026, 1, 12, hour: 17))
    }

    @Test func nextWorkingDayEOBFromWeekend() {
        // Saturday → Monday EOB.
        #expect(
            MoveToTomorrow(repository: InMemoryWorkItemRepository(), calendar: calendar)
                .nextWorkingDayEOB(after: TestDates.saturday)
            == TestDates.date(2026, 1, 12, hour: 17)
        )
    }

    @Test func notFoundThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: MoveToTomorrow.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new())
        }
    }
}
