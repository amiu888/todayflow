import Foundation
import Testing
import TodayFlowCore

struct DueNudgePlannerTests {
    private let now = TestDates.date(2026, 11, 3, hour: 8)

    private func task(_ title: String, dueIn hours: Double, createdHoursAgo: Double = 24) -> WorkItem {
        WorkItem(
            kind: .task,
            title: title,
            startAt: now.addingTimeInterval(-createdHoursAgo * 3600),
            endAt: now.addingTimeInterval(hours * 3600),
            displayOrder: "a",
            createdAt: now.addingTimeInterval(-createdHoursAgo * 3600)
        )
    }

    @Test func stage_picksTheTightestWindow() {
        #expect(DueNudgeStage.stage(remaining: 13 * 3600) == nil)
        #expect(DueNudgeStage.stage(remaining: 12 * 3600) == .twelveHours)
        #expect(DueNudgeStage.stage(remaining: 5 * 3600 + 1) == .twelveHours)
        #expect(DueNudgeStage.stage(remaining: 5 * 3600) == .fiveHours)
        #expect(DueNudgeStage.stage(remaining: 3600) == .oneHour)
        #expect(DueNudgeStage.stage(remaining: 60) == .oneHour)
        #expect(DueNudgeStage.stage(remaining: 0) == nil)
        #expect(DueNudgeStage.stage(remaining: -5) == nil)
    }

    @Test func eachStageFiresOnce_asTheDeadlineApproaches() {
        let planner = DueNudgePlanner()
        let item = task("Report", dueIn: 13)
        var memory: DueNudgePlanner.Memory = [:]

        // First sight, more than 12 hours out: nothing.
        #expect(planner.plan(items: [item], now: now, memory: &memory).isEmpty)

        func at(_ hours: Double) -> [DueNudgeStage] {
            planner.plan(
                items: [item],
                now: now.addingTimeInterval(hours * 3600),
                memory: &memory
            ).map(\.stage)
        }
        #expect(at(1.5) == [.twelveHours])   // 11.5 h left
        #expect(at(2) == [])                 // still the 12 h stage
        #expect(at(8.5) == [.fiveHours])     // 4.5 h left
        #expect(at(9) == [])
        #expect(at(12.2) == [.oneHour])      // 48 min left
        #expect(at(12.5) == [])
        #expect(at(14) == [])                // overdue
    }

    @Test func firstSight_isQuietUnlessInsideTheLastHour() {
        let planner = DueNudgePlanner()
        var memory: DueNudgePlanner.Memory = [:]
        let today = task("Due this afternoon", dueIn: 4)
        let urgent = task("Due in half an hour", dueIn: 0.5)
        let justMade = task("Just made", dueIn: 0.5, createdHoursAgo: 0.01)

        let nudges = planner.plan(items: [today, urgent, justMade], now: now, memory: &memory)
        #expect(nudges.map(\.title) == ["Due in half an hour"])
        // Nothing repeats on the next tick.
        #expect(planner.plan(items: [today, urgent, justMade], now: now.addingTimeInterval(30), memory: &memory).isEmpty)
    }

    @Test func reschedulingStartsOver_andFinishedTasksAreForgotten() {
        let planner = DueNudgePlanner()
        var memory: DueNudgePlanner.Memory = [:]
        var item = task("Report", dueIn: 13)
        _ = planner.plan(items: [item], now: now, memory: &memory)
        let later = now.addingTimeInterval(2 * 3600)
        #expect(planner.plan(items: [item], now: later, memory: &memory).count == 1)

        // Pushed out, then it comes round again: the 12 h popup shows again.
        item.endAt = later.addingTimeInterval(20 * 3600)
        #expect(planner.plan(items: [item], now: later, memory: &memory).isEmpty)
        let again = later.addingTimeInterval(9 * 3600)
        #expect(planner.plan(items: [item], now: again, memory: &memory).map(\.stage) == [.twelveHours])

        item.status = .done
        #expect(planner.plan(items: [item], now: again, memory: &memory).isEmpty)
        #expect(memory.isEmpty)
    }

    @Test func mostUrgentComesFirst() {
        let planner = DueNudgePlanner()
        var memory: DueNudgePlanner.Memory = [:]
        let a = task("A", dueIn: 13)
        let b = task("B", dueIn: 5.5)
        _ = planner.plan(items: [a, b], now: now, memory: &memory)
        let nudges = planner.plan(items: [a, b], now: now.addingTimeInterval(3600), memory: &memory)
        #expect(nudges.map(\.title) == ["B", "A"])
    }
}

struct TaskScheduleTests {
    @Test func startOfHour_dropsMinutesAndSeconds() {
        let date = TestDates.date(2026, 11, 17, hour: 13, minute: 34, second: 20)
        #expect(TaskSchedule.startOfHour(date, calendar: TestDates.calendar)
            == TestDates.date(2026, 11, 17, hour: 13))
    }

    @Test func dueAfterStart_pushesADueTimeThatIsNotAfterTheStart() {
        let start = TestDates.date(2026, 11, 17, hour: 13)
        let later = TestDates.date(2026, 11, 17, hour: 17)
        #expect(TaskSchedule.dueAfterStart(start: start, due: later) == later)
        #expect(TaskSchedule.dueAfterStart(start: start, due: start)
            == TestDates.date(2026, 11, 17, hour: 14))
        #expect(TaskSchedule.dueAfterStart(start: start, due: start.addingTimeInterval(-600))
            == TestDates.date(2026, 11, 17, hour: 14))
    }
}
