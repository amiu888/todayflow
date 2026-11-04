import Foundation
import Testing
@testable import TodayFlowCore

struct SetPriorityTests {
    private func makeUseCase() -> (SetPriority, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        return (SetPriority(repository: repo), repo)
    }

    @Test func setsPriority() async throws {
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task", priority: .normal)
        await repo.seed(item)

        let updated = try await uc.execute(item.id, to: .urgent)
        #expect(updated.priority == .urgent)
        #expect(updated.version == 2)
    }

    @Test func samePriorityThrows() async {
        let (uc, repo) = makeUseCase()
        let item = WorkItem(title: "Task", priority: .high)
        await repo.seed(item)
        await #expect(throws: SetPriority.Error.unchanged) {
            _ = try await uc.execute(item.id, to: .high)
        }
    }

    @Test func notFoundThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: SetPriority.Error.notFound) {
            _ = try await uc.execute(UUIDv7.new(), to: .low)
        }
    }
}
