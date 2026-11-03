import Foundation
import Testing
@testable import TodayFlowCore

struct CompleteTaskTests {
    private func makeUseCase() -> (CompleteTask, InMemoryWorkItemRepository, InMemoryLinkRepository) {
        let repo = InMemoryWorkItemRepository()
        let linkRepo = InMemoryLinkRepository()
        return (CompleteTask(repository: repo, linkRepository: linkRepo), repo, linkRepo)
    }

    @Test func completesOpenItem() async throws {
        let (uc, repo, _) = makeUseCase()
        let item = WorkItem(title: "Task")
        await repo.seed(item)
        let at = TestDates.date(2026, 1, 5, hour: 12)
        let done = try await uc.execute(item.id, at: at)
        #expect(done.status == .done)
        #expect(done.completedAt == at)
        #expect(done.version == 2) // bumped once
    }

    @Test func blockedItemThrowsUnlessForced() async throws {
        let (uc, repo, linkRepo) = makeUseCase()
        let a = WorkItem(title: "A", status: .todo)
        let b = WorkItem(title: "B", status: .todo)
        await repo.seed(a)
        await repo.seed(b)
        try await linkRepo.save(ItemLink(fromId: a.id, toId: b.id)) // A is B's prerequisite

        await #expect(throws: CompleteTask.Error.blocked) {
            _ = try await uc.execute(b.id)
        }
        let done = try await uc.execute(b.id, force: true)
        #expect(done.status == .done)
    }

    @Test func completingPrereqUnblocksDependent() async throws {
        // Acceptance: drag A onto B "Before" → B locked; completing A unlocks B.
        let (uc, repo, linkRepo) = makeUseCase()
        let a = WorkItem(title: "A", status: .todo)
        let b = WorkItem(title: "B", status: .todo)
        await repo.seed(a)
        await repo.seed(b)
        try await linkRepo.save(ItemLink(fromId: a.id, toId: b.id))

        await #expect(throws: CompleteTask.Error.blocked) {
            _ = try await uc.execute(b.id)
        }
        _ = try await uc.execute(a.id)
        let done = try await uc.execute(b.id) // re-derivation now sees A done
        #expect(done.status == .done)
    }

    @Test func alreadyTerminalThrows() async {
        let (uc, repo, _) = makeUseCase()
        let item = WorkItem(title: "Task", status: .done)
        await repo.seed(item)
        await #expect(throws: CompleteTask.Error.alreadyTerminal) {
            _ = try await uc.execute(item.id)
        }
    }

    @Test func notFoundThrows() async {
        let (uc, _, _) = makeUseCase()
        await #expect(throws: CompleteTask.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new())
        }
    }
}
