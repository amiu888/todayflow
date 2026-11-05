import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private let calendarTestCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}()

private let calendarNow = calendarTestCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 4, hour: 10)
)!

private func calendarDate(_ day: Int) -> Date {
    calendarTestCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: day, hour: 17)
    )!
}

struct CalendarViewModelTests {
    @Test @MainActor
    func weekContainsSevenDaysAndGroupsTasksByDueDate() async {
        let repository = InMemoryWorkItemRepository()
        let task = WorkItem(title: "Ship", startAt: calendarDate(4), endAt: calendarDate(5))
        await repository.seed(task)
        let model = CalendarViewModel(
            repository: repository,
            calendar: calendarTestCalendar,
            clock: { calendarNow }
        )

        await model.load()

        #expect(model.weekDays.count == 7)
        let thursday = model.weekDays.first {
            calendarTestCalendar.isDate($0.date, inSameDayAs: calendarDate(5))
        }
        #expect(thursday?.items.map(\.title) == ["Ship"])
    }

    @Test @MainActor
    func monthGridIsSixWeeksAndKeepsAdjacentDays() async {
        let model = CalendarViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: calendarTestCalendar,
            clock: { calendarNow }
        )

        await model.load()

        #expect(model.monthWeeks.count == 6)
        #expect(model.monthWeeks.allSatisfy { $0.count == 7 })
        #expect(model.monthWeeks.flatMap { $0 }.contains { $0.isToday })
    }

    @Test @MainActor
    func navigationMovesByWeekOrMonth() async {
        let model = CalendarViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: calendarTestCalendar,
            clock: { calendarNow }
        )
        await model.load()

        let nextWeek = calendarTestCalendar.startOfDay(for: calendarTestCalendar.date(byAdding: .day, value: 7, to: calendarNow)!)
        model.show(.week)
        model.next()
        #expect(model.anchor == nextWeek)

        model.show(.month)
        model.previous()
        let previousMonth = calendarTestCalendar.startOfDay(for: calendarTestCalendar.date(byAdding: .day, value: -30, to: nextWeek)!)
        #expect(model.anchor == previousMonth)
    }
}
