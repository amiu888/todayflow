import Foundation
import Testing
@testable import TodayFlowCore

struct RollUpProgressTests {
    private func makeUseCase() -> (RollUpProgress, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        let uc = RollUpProgress(repository: repo)
        return (uc, repo)
    }

    @Test func leafTaskIsSelf() async {
        let (uc, repo) = makeUseCase()
        let task = WorkItem(kind: .task, title: "T", status: .done)
        await repo.seed(task)
        let r = await uc.execute(task.id)
        #expect(r.done == 1)
        #expect(r.total == 1)
        #expect(r.fraction == 1.0)
        #expect(r.isComplete)
    }

    @Test func projectRollsUpItsTasks() async {
        let (uc, repo) = makeUseCase()
        let project = WorkItem(kind: .project, title: "P")
        await repo.seed(project)
        await repo.seed(WorkItem(kind: .task, title: "T1", parentId: project.id, status: .done))
        await repo.seed(WorkItem(kind: .task, title: "T2", parentId: project.id, status: .todo))
        await repo.seed(WorkItem(kind: .task, title: "T3", parentId: project.id, status: .done))

        let r = await uc.execute(project.id)
        #expect(r.total == 3)
        #expect(r.done == 2)
        #expect(abs(r.fraction - 2.0 / 3.0) < 1e-9)
        #expect(!r.isComplete)
    }

    @Test func epicIsTaskCountWeightedAverage() async {
        let (uc, repo) = makeUseCase()
        let epic = WorkItem(kind: .epic, title: "E")
        await repo.seed(epic)
        let p1 = WorkItem(kind: .project, title: "P1", parentId: epic.id)
        await repo.seed(p1)
        await repo.seed(WorkItem(kind: .task, title: "a", parentId: p1.id, status: .done))
        await repo.seed(WorkItem(kind: .task, title: "b", parentId: p1.id, status: .todo))
        let p2 = WorkItem(kind: .project, title: "P2", parentId: epic.id)
        await repo.seed(p2)
        await repo.seed(WorkItem(kind: .task, title: "c", parentId: p2.id, status: .done))
        await repo.seed(WorkItem(kind: .task, title: "d", parentId: p2.id, status: .done))

        let r = await uc.execute(epic.id)
        #expect(r.total == 4)
        #expect(r.done == 3)
        #expect(abs(r.fraction - 0.75) < 1e-9)
    }

    @Test func missingItemIsZero() async {
        let (uc, _) = makeUseCase()
        let r = await uc.execute(UUIDv7.new())
        #expect(r.total == 0)
        #expect(r.fraction == 0)
        #expect(!r.isComplete)
    }
}
