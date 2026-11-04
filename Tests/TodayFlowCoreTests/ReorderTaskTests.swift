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

    // MARK: toTopLevel (driver.md FR-16 hierarchy refinement)

    @Test func toTopLevel_detachesChildAboveExistingTopLevel() async throws {
        let (uc, repo) = makeUseCase()
        let epic = WorkItem(kind: .epic, title: "E", displayOrder: "1")
        let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "5")
        let otherTop = WorkItem(kind: .epic, title: "O", displayOrder: "9")
        await repo.seed(epic); await repo.seed(project); await repo.seed(otherTop)

        let moved = try await uc.execute(project.id, beforeId: epic.id, toTopLevel: true)

        #expect(moved.parentId == nil)
        // `midpoint(nil, firstTopLevelKey)` sorts strictly above the first top-level item.
        #expect(FractionalIndex.isLessThan(moved.displayOrder, epic.displayOrder))
        let top = await repo.children(of: nil)
        #expect(top.first?.id == project.id)
        #expect((await repo.item(project.id))?.parentId == nil) // persisted
    }

    @Test func toTopLevel_emptyTopLevel() async throws {
        let (uc, repo) = makeUseCase()
        let epic = WorkItem(kind: .epic, title: "E")
        let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "5")
        await repo.seed(epic); await repo.seed(project)

        let moved = try await uc.execute(project.id, toTopLevel: true)

        #expect(moved.parentId == nil)
        let top = await repo.children(of: nil)
        #expect(top.map(\.id) == [epic.id, project.id])
    }

    @Test func toTopLevel_winsOverNewParentId() async throws {
        let (uc, repo) = makeUseCase()
        let epic = WorkItem(kind: .epic, title: "E")
        let otherEpic = WorkItem(kind: .epic, title: "O2")
        let project = WorkItem(kind: .project, title: "P", parentId: epic.id)
        await repo.seed(epic); await repo.seed(otherEpic); await repo.seed(project)

        let moved = try await uc.execute(project.id, newParentId: otherEpic.id, toTopLevel: true)

        #expect(moved.parentId == nil)
    }

    // MARK: newDisplayOrder (driver.md FR-12 flat-list reorder primitive)

    @Test func newDisplayOrder_setsExplicitKeyAndKeepsParent() async throws {
        let (uc, repo) = makeUseCase()
        let project = WorkItem(kind: .project, title: "P")
        let task = WorkItem(kind: .task, title: "T", parentId: project.id, displayOrder: "1")
        await repo.seed(project); await repo.seed(task)

        let moved = try await uc.execute(task.id, newDisplayOrder: "zz")

        #expect(moved.displayOrder == "zz")
        #expect(moved.parentId == project.id)
        #expect((await repo.item(task.id))?.displayOrder == "zz") // persisted
    }

    @Test func newDisplayOrder_winsOverBeforeAfter() async throws {
        let (uc, repo) = makeUseCase()
        let a = WorkItem(title: "A", displayOrder: "1")
        let c = WorkItem(title: "C", displayOrder: "9")
        let b = WorkItem(title: "B", displayOrder: "0")
        await repo.seed(a); await repo.seed(c); await repo.seed(b)

        let moved = try await uc.execute(b.id, beforeId: c.id, afterId: a.id, newDisplayOrder: "7")

        #expect(moved.displayOrder == "7")
    }
}
