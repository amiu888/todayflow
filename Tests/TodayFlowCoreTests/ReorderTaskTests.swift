import Foundation
import Testing
@testable import TodayFlowCore

struct ReorderTaskTests {
    private func makeUseCase() -> (ReorderTask, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        return (ReorderTask(repository: repo), repo)
    }

    @Test func movesToTop() async throws {
        let (uc, repo) = makeUseCase()
        let a = WorkItem(title: "A", displayOrder: "1")
        let b = WorkItem(title: "B", displayOrder: "5")
        let c = WorkItem(title: "C", displayOrder: "9")
        await repo.seed(a); await repo.seed(b); await repo.seed(c)

        let moved = try await uc.execute(c.id, beforeId: a.id, afterId: nil)
        #expect(FractionalIndex.isLessThan(moved.displayOrder, a.displayOrder))
        #expect((await repo.item(c.id))?.displayOrder == moved.displayOrder) // persisted
    }

    @Test func movesToBottom() async throws {
        let (uc, repo) = makeUseCase()
        let a = WorkItem(title: "A", displayOrder: "1")
        let b = WorkItem(title: "B", displayOrder: "5")
        let c = WorkItem(title: "C", displayOrder: "9")
        await repo.seed(a); await repo.seed(b); await repo.seed(c)

        let moved = try await uc.execute(a.id, beforeId: nil, afterId: c.id)
        #expect(FractionalIndex.isLessThan(c.displayOrder, moved.displayOrder))
    }

    @Test func insertsBetweenNeighbors() async throws {
        let (uc, repo) = makeUseCase()
        let a = WorkItem(title: "A", displayOrder: "1")
        let c = WorkItem(title: "C", displayOrder: "9")
        let b = WorkItem(title: "B", displayOrder: "0") // starts above a
        await repo.seed(a); await repo.seed(c); await repo.seed(b)

        let moved = try await uc.execute(b.id, beforeId: c.id, afterId: a.id)
        #expect(FractionalIndex.isLessThan(a.displayOrder, moved.displayOrder))
        #expect(FractionalIndex.isLessThan(moved.displayOrder, c.displayOrder))
    }

    @Test func reparentValidatesHierarchy() async {
        let (uc, repo) = makeUseCase()
        let task = WorkItem(kind: .task, title: "T")
        let otherTask = WorkItem(kind: .task, title: "T2")
        await repo.seed(task); await repo.seed(otherTask)
        await #expect(throws: ReorderTask.Error.invalidParent(kind: .task, parentKind: .task)) {
            _ = try await uc.execute(task.id, newParentId: otherTask.id)
        }
    }

    @Test func reparentToProjectSucceeds() async throws {
        let (uc, repo) = makeUseCase()
        let task = WorkItem(kind: .task, title: "T")
        let project = WorkItem(kind: .project, title: "P")
        await repo.seed(task); await repo.seed(project)
        let moved = try await uc.execute(task.id, newParentId: project.id)
        #expect(moved.parentId == project.id)
    }

    @Test func notFoundThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: ReorderTask.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new())
        }
    }
}
