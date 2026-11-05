import Foundation
import Testing
import TodayFlowCore

private let plannerCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let plannerWorkCalendar = WorkCalendar(calendar: plannerCalendar)

private func plannerDate(_ hour: Int, _ minute: Int = 0) -> Date {
    plannerCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 3, hour: hour, minute: minute)
    )!
}

private func plannerItem(
    _ title: String,
    endAt: Date,
    priority: Priority = .normal,
    status: Status = .todo
) -> WorkItem {
    WorkItem(
        title: title,
        status: status,
        priority: priority,
        startAt: plannerDate(9),
        endAt: endAt,
        displayOrder: "a0"
    )
}

struct NudgePlannerTests {
    @Test func noOpenItems_noNudges() {
        let nudges = NudgePlanner().plan(
            openItems: [],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )
        #expect(nudges.isEmpty)
    }

    @Test func endOfDay_leadsAreTwoHoursAndThirtyMinutes() {
        let item = plannerItem("Alpha", endAt: plannerDate(17))
        let nudges = NudgePlanner().plan(
            openItems: [item],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )

        let endOfDay = nudges.filter {
            if case .endOfDay = $0.kind { return true }
            return false
        }
        #expect(endOfDay.count == 2)
        #expect(endOfDay.map(\.fireAt) == [plannerDate(15), plannerDate(16, 30)])
        #expect(endOfDay.allSatisfy { $0.itemId == nil })
    }

    @Test func taskReminder_firesThirtyMinutesBeforeEndAt() {
        let item = plannerItem("Alpha", endAt: plannerDate(17))
        let nudges = NudgePlanner().plan(
            openItems: [item],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )

        let task = nudges.first { $0.kind == .task(item.id) }
        #expect(task?.fireAt == plannerDate(16, 30))
        #expect(task?.title == "Alpha")
        #expect(task?.itemId == item.id)
    }

    @Test func pastNudges_areDropped() {
        let item = plannerItem("Alpha", endAt: plannerDate(16))
        let nudges = NudgePlanner().plan(
            openItems: [item],
            calendar: plannerWorkCalendar,
            now: plannerDate(16, 45)
        )
        #expect(nudges.isEmpty)
    }

    @Test func completedAndCancelledItems_areIgnored() {
        let done = plannerItem("Done", endAt: plannerDate(17), status: .done)
        let cancelled = plannerItem("Cancelled", endAt: plannerDate(17), status: .cancelled)
        let nudges = NudgePlanner().plan(
            openItems: [done, cancelled],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )
        #expect(nudges.isEmpty)
    }

    @Test func urgentTask_raisesTheEndOfDayNudgeToP1() {
        let normal = plannerItem("Normal", endAt: plannerDate(17), priority: .normal)
        let urgent = plannerItem("Urgent", endAt: plannerDate(17), priority: .urgent)
        let nudges = NudgePlanner().plan(
            openItems: [normal, urgent],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )
        let endOfDay = nudges.first {
            if case .endOfDay = $0.kind { return true }
            return false
        }
        #expect(endOfDay?.priority == .urgent)
        #expect(endOfDay?.isUrgent == true)
    }

    @Test func ids_areStableAcrossPlans() {
        let item = plannerItem("Alpha", endAt: plannerDate(17))
        let first = NudgePlanner().plan(
            openItems: [item],
            calendar: plannerWorkCalendar,
            now: plannerDate(14)
        )
        let second = NudgePlanner().plan(
            openItems: [item],
            calendar: plannerWorkCalendar,
            now: plannerDate(14, 5)
        )
        #expect(first.map(\.id) == second.map(\.id))
    }
}
