import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private let focusCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let focusNow = focusCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 4, hour: 10)
)!

private let focusDue = focusCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 4, hour: 17)
)!

@MainActor
private final class FocusCloseLog {
    private(set) var count = 0
    func record() { count += 1 }
}

struct FocusViewModelTests {
    @Test @MainActor
    func loadStartsAFocusSessionAndCompleteClosesIt() async {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(title: "Deep work", startAt: focusNow, endAt: focusDue)
        await repository.seed(item)
        let log = FocusCloseLog()

        let model = FocusViewModel(
            itemId: item.id,
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            clock: { focusNow },
            onClosed: { [log] in log.record() }
        )
        await model.load()

        #expect(model.item?.title == "Deep work")
        #expect(model.total == 25 * 60)
        #expect(model.isRunning)
        model.pause()

        await model.complete()

        #expect(await repository.item(item.id)?.status == .done)
        #expect(log.count == 1)
    }

    @Test @MainActor
    func extendAddsFiveMinutes() async {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(title: "Deep work", startAt: focusNow, endAt: focusDue)
        await repository.seed(item)
        let model = FocusViewModel(
            itemId: item.id,
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            clock: { focusNow }
        )
        await model.load()
        model.pause()

        let before = model.remaining
        model.extend()
        model.pause()

        #expect(model.remaining >= before + 299)
    }
}
