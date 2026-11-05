import Foundation
import Testing
import TodayFlowCore

private let startCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let startWork = WorkCalendar(
    startHour: 9,
    endHour: 17,
    workWeekdays: [2, 3, 4, 5, 6],
    calendar: startCalendar
)

private func startDate(_ day: Int, hour: Int = 9) -> Date {
    startCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: day, hour: hour)
    )!
}

struct SetStartTimeTests {
    @Test func movesStartAndKeepsAValidDueTime() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "Plan",
            startAt: startDate(4),
            endAt: startDate(4, hour: 17)
        )
        await repository.seed(item)

        let updated = try await SetStartTime(repository: repository, calendar: startWork)
            .execute(item.id, to: startDate(4, hour: 14), at: startDate(4, hour: 10))

        #expect(updated.startAt == startDate(4, hour: 14))
        #expect(updated.endAt == startDate(4, hour: 17))
    }

    @Test func movingPastTheDueTimeRecomputesDue() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "Plan",
            startAt: startDate(4),
            endAt: startDate(4, hour: 17)
        )
        await repository.seed(item)

        let updated = try await SetStartTime(repository: repository, calendar: startWork)
            .execute(item.id, to: startDate(5, hour: 9), at: startDate(4, hour: 10))

        #expect(updated.startAt == startDate(5, hour: 9))
        #expect(updated.endAt == startDate(5, hour: 17))
    }

    @Test func missingItemThrows() async throws {
        let repository = InMemoryWorkItemRepository()
        await #expect(throws: SetStartTime.Error.notFound) {
            try await SetStartTime(repository: repository, calendar: startWork)
                .execute(UUIDv7.new(), to: startDate(4))
        }
    }
}
