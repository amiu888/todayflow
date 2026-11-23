import CoreGraphics
import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Task window stack")
struct TaskWindowStackTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ title: String, _ priority: Priority, dueIn hours: Double, openedAgo minutes: Double) -> TaskWindowEntry {
        TaskWindowEntry(
            id: .new(), title: title, priority: priority,
            dueAt: now.addingTimeInterval(hours * 3_600), openedAt: now.addingTimeInterval(-minutes * 60)
        )
    }

    @Test func sortsByPriorityDueRecentAndManual() {
        let a = entry("A", .low, dueIn: 1, openedAgo: 5)
        let b = entry("B", .urgent, dueIn: 30, openedAgo: 1)
        let c = entry("C", .high, dueIn: 2, openedAgo: 10)
        let all = [a, b, c]
        #expect(TaskWindowStack.sorted(all, by: .priority).map(\.title) == ["B", "C", "A"])
        #expect(TaskWindowStack.sorted(all, by: .due).map(\.title) == ["A", "C", "B"])
        #expect(TaskWindowStack.sorted(all, by: .recent).map(\.title) == ["B", "A", "C"])
        #expect(TaskWindowStack.sorted(all, by: .manual, manual: [c.id, a.id]).map(\.title) == ["C", "A", "B"])
    }

    @Test func titlesSayPriorityAndWhenItIsDue() {
        let today = entry("Patch db", .urgent, dueIn: 2, openedAgo: 0)
        #expect(TaskWindowStack.windowTitle(today, now: now, calendar: calendar).hasPrefix("P1 · Due "))
        #expect(TaskWindowStack.windowTitle(today, now: now, calendar: calendar).hasSuffix(" — Patch db"))
        let late = entry("Invoice", .high, dueIn: -1, openedAgo: 0)
        #expect(TaskWindowStack.dueLabel(late, now: now, calendar: calendar) == "P2 · Overdue")
        var done = late
        done.isDone = true
        #expect(TaskWindowStack.dueLabel(done, now: now, calendar: calendar) == "Done")
    }

    @Test func aStackShowsEveryTitleBarAboveTheFrontWindow() {
        let area = CGRect(x: 400, y: 0, width: 1000, height: 900)
        let frames = TaskWindowStack.stackFrames(count: 3, windowSize: CGSize(width: 720, height: 640), area: area)
        #expect(frames.count == 3)
        // The back window touches the top; each nearer window is 30 pt lower.
        #expect(frames[2].maxY == 900)
        #expect(frames[1].maxY == 870)
        #expect(frames[0].maxY == 840)
        #expect(frames.allSatisfy { $0.minX == 400 && $0.width == 720 })
    }

    @Test func aTallStackShrinksToFitTheScreen() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let frames = TaskWindowStack.stackFrames(count: 10, windowSize: CGSize(width: 720, height: 640), area: area)
        #expect(frames.allSatisfy { $0.minY >= 0 && $0.maxY <= 700 })
        #expect(frames[0].height >= 360)
        // Titles still step down in order.
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxY < $1.maxY })
    }

    @Test func tilesFillTheAreaInColumns() {
        let area = CGRect(x: 0, y: 0, width: 1500, height: 900)
        let frames = TaskWindowStack.tileFrames(count: 4, area: area)
        #expect(frames.count == 4)
        #expect(Set(frames.map(\.minY)).count == 2) // 3 columns fit, so 2 rows
        #expect(frames.allSatisfy { area.contains($0) })
    }
}
