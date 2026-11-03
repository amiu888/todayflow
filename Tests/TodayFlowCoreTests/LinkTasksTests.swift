import Foundation
import Testing
@testable import TodayFlowCore

struct LinkTasksTests {
    private func makeUseCase() -> (LinkTasks, InMemoryWorkItemRepository, InMemoryLinkRepository) {
        let repo = InMemoryWorkItemRepository()
        let linkRepo = InMemoryLinkRepository()
        let uc = LinkTasks(linkRepository: linkRepo, itemRepository: repo)
        return (uc, repo, linkRepo)
    }

    @Test func createsBlocksLink() async throws {
        let (uc, repo, linkRepo) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        await repo.seed(a)
        await repo.seed(b)

        let link = try await uc.execute(from: a.id, to: b.id)
        #expect(link.kind == .blocks)
        #expect(link.fromId == a.id)
        #expect(link.toId == b.id)
        #expect((await linkRepo.links(to: b.id)).contains { $0.id == link.id })

        // Acceptance: a prerequisite makes its dependent read as blocked.
        #expect(StatusDeriver().derive(stored: b.status, blockers: [a]) == .blocked)
    }

    @Test func selfLinkThrows() async {
        let (uc, repo, _) = makeUseCase()
        let a = WorkItem(title: "A")
        await repo.seed(a)
        await #expect(throws: LinkTasks.Error.selfLink) {
            _ = try await uc.execute(from: a.id, to: a.id)
        }
    }

    @Test func duplicateThrows() async throws {
        let (uc, repo, _) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        await repo.seed(a)
        await repo.seed(b)
        _ = try await uc.execute(from: a.id, to: b.id)
        await #expect(throws: LinkTasks.Error.duplicate) {
            _ = try await uc.execute(from: a.id, to: b.id)
        }
    }

    @Test func loopThrows() async throws {
        // Acceptance: linking B → A when A → B exists is rejected ("would create a loop").
        let (uc, repo, _) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        await repo.seed(a)
        await repo.seed(b)
        _ = try await uc.execute(from: a.id, to: b.id) // A → B
        await #expect(throws: LinkTasks.Error.wouldCreateLoop) {
            _ = try await uc.execute(from: b.id, to: a.id)
        }
    }

    @Test func transitiveLoopThrows() async throws {
        let (uc, repo, _) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        let c = WorkItem(title: "C")
        await repo.seed(a)
        await repo.seed(b)
        await repo.seed(c)
        _ = try await uc.execute(from: a.id, to: b.id) // A → B
        _ = try await uc.execute(from: b.id, to: c.id) // B → C
        await #expect(throws: LinkTasks.Error.wouldCreateLoop) {
            _ = try await uc.execute(from: c.id, to: a.id)
        }
    }

    @Test func chainFullThrows() async throws {
        // Linked-list shape: an item has at most one predecessor and one successor.
        let (uc, repo, _) = makeUseCase()
        let a = WorkItem(title: "A")
        let b = WorkItem(title: "B")
        let c = WorkItem(title: "C")
        await repo.seed(a)
        await repo.seed(b)
        await repo.seed(c)
        _ = try await uc.execute(from: a.id, to: b.id) // B already has predecessor A
        await #expect(throws: LinkTasks.Error.chainFull) {
            _ = try await uc.execute(from: c.id, to: b.id)
        }
    }

    @Test func notFoundThrows() async {
        let (uc, _, _) = makeUseCase()
        await #expect(throws: LinkTasks.Error.notFound) {
            _ = try await uc.execute(from: UUIDv7.new(), to: UUIDv7.new())
        }
    }
}
