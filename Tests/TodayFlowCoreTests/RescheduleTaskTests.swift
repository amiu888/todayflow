import Foundation
import Testing
import TodayFlowCore

private let rescheduleCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let rescheduleWork = WorkCalendar(
    startHour: 9,
    endHour: 17,
    workWeekdays: [2, 3, 4, 5, 6],
    calendar: rescheduleCalendar
)

private func rescheduleDate(
    _ year: Int, _ month: Int, _ day: Int,
    hour: Int = 0, minute: Int = 0
) -> Date {
    rescheduleCalendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    )!
}

struct RescheduleTaskTests {
    @Test func movesDueTimeToTheChosenDaysEndOfBusiness() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "Report",
            startAt: rescheduleDate(2026, 11, 3, hour: 9),
            endAt: rescheduleDate(2026, 11, 3, hour: 17),
            displayOrder: "a1"
        )
        await repository.seed(item)

        let updated = try await RescheduleTask(
            repository: repository,
            calendar: rescheduleWork
        ).execute(
            item.id,
            to: rescheduleDate(2026, 11, 10),
            at: rescheduleDate(2026, 11, 3, hour: 17, minute: 30)
        )

        #expect(updated.endAt == rescheduleDate(2026, 11, 10, hour: 17))
        // The start stayed on its original day because it is still before the
        // new due time.
        #expect(updated.startAt == item.startAt)
    }

    @Test func movesStartForwardWhenItWouldFallAfterTheNewDueTime() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "Late task",
            startAt: rescheduleDate(2026, 11, 3, hour: 9),
            endAt: rescheduleDate(2026, 11, 3, hour: 17),
            displayOrder: "a1"
        )
        await repository.seed(item)

        let updated = try await RescheduleTask(
            repository: repository,
            calendar: rescheduleWork
        ).execute(
            item.id,
            to: rescheduleDate(2026, 11, 2),
            at: rescheduleDate(2026, 11, 1, hour: 10)
        )

        #expect(updated.endAt == rescheduleDate(2026, 11, 2, hour: 17))
        #expect(updated.startAt == rescheduleDate(2026, 11, 2, hour: 9))
    }

    @Test func rejectsADayThatIsAlreadyOver() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "Old task",
            startAt: rescheduleDate(2026, 11, 3, hour: 9),
            endAt: rescheduleDate(2026, 11, 3, hour: 17),
            displayOrder: "a1"
        )
        await repository.seed(item)

        await #expect(throws: RescheduleTask.Error.dateInPast) {
            try await RescheduleTask(repository: repository, calendar: rescheduleWork).execute(
                item.id,
                to: rescheduleDate(2026, 11, 3),
                at: rescheduleDate(2026, 11, 3, hour: 18)
            )
        }
        #expect(await repository.item(item.id)?.endAt == item.endAt)
    }

    @Test func missingItemThrows() async throws {
        let repository = InMemoryWorkItemRepository()
        await #expect(throws: RescheduleTask.Error.notFound) {
            try await RescheduleTask(repository: repository, calendar: rescheduleWork).execute(
                UUIDv7.new(),
                to: rescheduleDate(2026, 11, 10),
                at: rescheduleDate(2026, 11, 3, hour: 10)
            )
        }
    }
}
