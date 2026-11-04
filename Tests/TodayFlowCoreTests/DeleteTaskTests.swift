import Foundation
import Testing
@testable import TodayFlowCore

struct DeleteTaskTests {
    private func makeUseCase() -> (DeleteTask, InMemoryWorkItemRepository, InMemoryLinkRepository) {
        let repo = InMemoryWorkItemRepository()
        let linkRepo = InMemoryLinkRepository()
        let uc = DeleteTask(itemRepository: repo, linkRepository: linkRepo)
        return (uc, repo, linkRepo)
    }

    @Test func reconnectsMiddleOfChain() async throws {
        // Acceptance: deleting B from A → B → C reconnects the chain to A → C.
        let (uc, repo, linkRepo) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        let c = WorkItem(title: "C")
        await repo.seed(a)
        await repo.seed(b)
        await repo.seed(c)
        try await linkRepo.save(ItemLink(fromId: a.id, toId: b.id)) // A → B
        try await linkRepo.save(ItemLink(fromId: b.id, toId: c.id)) // B → C

        _ = try await uc.execute(b.id)

        #expect(await repo.item(b.id) == nil) // soft-deleted
        let links = await linkRepo.allLinks()
        #expect(links.contains { $0.kind == .blocks && $0.fromId == a.id && $0.toId == c.id })
        #expect(!links.contains { $0.fromId == b.id || $0.toId == b.id })
    }

    @Test func softDeletesButPreservesChildrenUnparented() async throws {
        // driver.md §2: deleting a parent never deletes children by default;
        // they become unparented.
        let (uc, repo, _) = makeUseCase()
        let project = WorkItem(kind: .project, title: "P")
        let task = WorkItem(kind: .task, title: "T", parentId: project.id)
        await repo.seed(project)
        await repo.seed(task)

        _ = try await uc.execute(project.id)

        #expect(await repo.item(project.id) == nil)
        let child = await repo.item(task.id)
        #expect(child != nil) // children are preserved
        #expect(child?.parentId == nil) // … but unparented
    }

    @Test func deleteWithChildrenRemovesDescendants() async throws {
        // The explicit "delete with children" option: the whole subtree goes.
        let (uc, repo, linkRepo) = makeUseCase()
        let epic = WorkItem(kind: .epic, title: "E")
        let project = WorkItem(kind: .project, title: "P", parentId: epic.id)
        let task = WorkItem(kind: .task, title: "T", parentId: project.id)
        let subtask = WorkItem(kind: .subtask, title: "S", parentId: task.id)
        let keep = WorkItem(kind: .task, title: "Keep")
        await repo.seed(epic)
        await repo.seed(project)
        await repo.seed(task)
        await repo.seed(subtask)
        await repo.seed(keep)
        try await linkRepo.save(ItemLink(fromId: task.id, toId: keep.id)) // T → Keep

        _ = try await uc.execute(epic.id, withChildren: true)

        #expect(await repo.item(epic.id) == nil)
        #expect(await repo.item(project.id) == nil)
        #expect(await repo.item(task.id) == nil)
        #expect(await repo.item(subtask.id) == nil)
        #expect(await repo.item(keep.id) != nil) // a sibling of the subtree survives
        let links = await linkRepo.allLinks()
        #expect(!links.contains { $0.fromId == task.id || $0.toId == task.id })
    }

    @Test func deletingStartOfChainJustRemovesItsLink() async throws {
        let (uc, repo, linkRepo) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        await repo.seed(a)
        await repo.seed(b)
        try await linkRepo.save(ItemLink(fromId: a.id, toId: b.id)) // A → B

        _ = try await uc.execute(a.id)

        #expect(await repo.item(a.id) == nil)
        #expect(await repo.item(b.id) != nil)
        #expect((await linkRepo.allLinks()).isEmpty)
    }

    @Test func notFoundThrows() async {
        let (uc, _, _) = makeUseCase()
        await #expect(throws: DeleteTask.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new())
        }
    }
}
