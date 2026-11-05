import Foundation
import Testing
@testable import TodayFlowCore

struct StatusTests {
    @Test func isCompleteOnlyDone() {
        #expect(Status.done.isComplete)
        #expect(!Status.todo.isComplete)
        #expect(!Status.inProgress.isComplete)
        #expect(!Status.blocked.isComplete)
        #expect(!Status.cancelled.isComplete)
    }

    @Test func isTerminalDoneOrCancelled() {
        #expect(Status.done.isTerminal)
        #expect(Status.cancelled.isTerminal)
        #expect(!Status.todo.isTerminal)
        #expect(!Status.inProgress.isTerminal)
        #expect(!Status.blocked.isTerminal)
    }

    @Test func labelsAndSymbols() {
        #expect(Status.blocked.label == "Blocked")
        #expect(Status.blocked.symbolName == "exclamationmark.circle")
        #expect(Status.done.symbolName == "checkmark.circle.fill")
    }
}

struct PriorityTests {
    @Test func orderingUrgentFirst() {
        #expect(Priority.urgent < Priority.high)
        #expect(Priority.high < Priority.normal)
        #expect(Priority.normal < Priority.low)
        #expect(Priority.urgent < Priority.low)
    }

    @Test func defaultIsNormal() {
        #expect(Priority.default == .normal)
    }

    @Test func labels() {
        #expect(Priority.urgent.label == "P1 Critical")
        #expect(Priority.normal.label == "P3 Medium")
    }
}

struct WorkItemDerivedTests {
    @Test func isDeletedReflectsDeletedAt() {
        var item = WorkItem(title: "x")
        #expect(!item.isDeleted)
        item.deletedAt = .now
        #expect(item.isDeleted)
    }

    @Test func isCompleteFollowsStatus() {
        var item = WorkItem(title: "x")
        #expect(!item.isComplete)
        item.status = .done
        #expect(item.isComplete)
    }

    @Test func touchingBumpsVersionAndStamps() {
        let item = WorkItem(title: "x")
        let v = item.version
        let now = TestDates.date(2026, 1, 5, hour: 10)
        let updated = item.touching(now)
        #expect(updated.version == v + 1)
        #expect(updated.updatedAt == now)
        #expect(item.version == v) // value type: original unchanged
    }

    @Test func hierarchyRules() {
        let epic = WorkItem.Kind.epic.allowedParentKinds
        #expect(epic.count == 1)
        #expect(epic.contains(nil))

        let project = WorkItem.Kind.project.allowedParentKinds
        #expect(project.contains(.epic))
        #expect(project.contains(nil))
        #expect(!project.contains(.project))

        let task = WorkItem.Kind.task.allowedParentKinds
        #expect(task.contains(.project))
        #expect(task.contains(nil))
        #expect(!task.contains(.epic))

        let subtask = WorkItem.Kind.subtask.allowedParentKinds
        #expect(subtask.contains(.task))
        #expect(subtask.contains(nil))
        #expect(!subtask.contains(.project))
    }
}
