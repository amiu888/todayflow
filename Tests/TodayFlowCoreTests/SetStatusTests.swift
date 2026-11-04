import Foundation
import Testing
@testable import TodayFlowCore

struct SetStatusTests {
    private func makeUseCase() -> (SetStatus, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        return (SetStatus(repository: repo), repo)
    }

    @Test func doneStampsCompletedAt() async throws {
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task", status: .inProgress)
        await repo.seed(item)
        let at = TestDates.date(2026, 1, 5, hour: 12)

        let done = try await uc.execute(item.id, to: .done, at: at)
        #expect(done.status == .done)
        #expect(done.completedAt == at)
        #expect(done.version == 2)
    }

    @Test func undoRestoresPreviousStatusAndClearsCompletedAt() async throws {
        // Acceptance (FR-14): complete, then undo → back to the previous state.
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task", status: .inProgress)
        await repo.seed(item)
        let at = TestDates.date(2026, 1, 5, hour: 12)

        _ = try await uc.execute(item.id, to: .done, at: at)
        let undone = try await uc.execute(item.id, to: .inProgress, at: TestDates.date(2026, 1, 5, hour: 12, minute: 1))
        #expect(undone.status == .inProgress)
        #expect(undone.completedAt == nil)
        #expect(undone.version == 3)
    }

    @Test func sameStatusThrows() async {
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task", status: .todo)
        await repo.seed(item)
        await #expect(throws: SetStatus.Error.unchanged) {
            _ = try await uc.execute(item.id, to: .todo)
        }
    }

    @Test func notFoundThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: SetStatus.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new(), to: .done)
        }
    }
}
