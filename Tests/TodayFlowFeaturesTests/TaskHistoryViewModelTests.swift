import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@MainActor
struct TaskHistoryViewModelTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func task(_ title: String, due: Date, status: Status = .todo, completedAt: Date? = nil) -> WorkItem {
        var item = WorkItem(
            kind: .task,
            title: title,
            status: status,
            startAt: due.addingTimeInterval(-3600),
            endAt: due,
            displayOrder: "a"
        )
        item.completedAt = completedAt
        return item
    }

    private func makeModel() async -> TaskHistoryViewModel {
        let repository = InMemoryWorkItemRepository()
        let now = date(17, hour: 10)
        for item in [
            task("Due later today", due: date(17, hour: 17)),
            task("Next week", due: date(24)),
            task("Missed last week", due: date(10)),
            task("Finished last week", due: date(11), status: .done, completedAt: date(11, hour: 9)),
            task("Finished today", due: date(17, hour: 16), status: .done, completedAt: date(17, hour: 9)),
        ] {
            await repository.seed(item)
        }
        let model = TaskHistoryViewModel(repository: repository, calendar: calendar, clock: { now })
        await model.load()
        return model
    }

    private func titles(_ model: TaskHistoryViewModel) -> [String] {
        model.groups.flatMap(\.items).map(\.title)
    }

    @Test func all_listsEveryTaskNewestDateFirst() async {
        let model = await makeModel()
        #expect(titles(model) == [
            "Next week", "Due later today", "Finished today",
            "Finished last week", "Missed last week",
        ])
        #expect(model.groups.count == 4)
        #expect(model.counts[.all] == 5)
    }

    @Test func filters_dueToday_past_completed() async {
        let model = await makeModel()
        model.filter = .dueToday
        #expect(titles(model) == ["Due later today"])
        model.filter = .past
        #expect(titles(model) == ["Finished last week", "Missed last week"])
        model.filter = .completed
        #expect(titles(model) == ["Finished today", "Finished last week"])
        #expect(model.counts == [.all: 5, .dueToday: 1, .past: 2, .completed: 2])
    }

    @Test func dateRange_keepsOnlyTasksDatedInside_inEitherOrder() async {
        let model = await makeModel()
        model.rangeFrom = date(11)
        model.rangeTo = date(10)
        model.usesDateRange = true
        #expect(titles(model) == ["Finished last week", "Missed last week"])
        #expect(model.counts[.all] == 2)

        model.filter = .completed
        #expect(titles(model) == ["Finished last week"])

        model.usesDateRange = false
        #expect(model.resultCount == 2)
    }
}
