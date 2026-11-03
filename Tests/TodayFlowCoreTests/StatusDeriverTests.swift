import Foundation
import Testing
@testable import TodayFlowCore

struct StatusDeriverTests {
    private let deriver = StatusDeriver()

    @Test func noBlockersKeepsStoredStatus() {
        #expect(deriver.derive(stored: .todo, blockers: []) == .todo)
        #expect(deriver.derive(stored: .inProgress, blockers: []) == .inProgress)
    }

    @Test func unresolvedBlockerDerivesBlocked() {
        let blocker = WorkItem(title: "prereq", status: .todo)
        #expect(deriver.derive(stored: .todo, blockers: [blocker]) == .blocked)
    }

    @Test func resolvedBlockerKeepsStoredStatus() {
        let blocker = WorkItem(title: "prereq", status: .done)
        #expect(deriver.derive(stored: .todo, blockers: [blocker]) == .todo)
    }

    @Test func terminalStatusIsNeverDerivedBlocked() {
        let blocker = WorkItem(title: "prereq", status: .todo)
        #expect(deriver.derive(stored: .done, blockers: [blocker]) == .done)
        #expect(deriver.derive(stored: .cancelled, blockers: [blocker]) == .cancelled)
    }

    @Test func anyUnresolvedBlockerIsEnough() {
        let done = WorkItem(title: "done", status: .done)
        let open = WorkItem(title: "open", status: .inProgress)
        #expect(deriver.derive(stored: .todo, blockers: [done, open]) == .blocked)
    }
}
