import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

struct ActionItemRepositoryTests {
    @Test func savesListsTogglesAndDeletes() async throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        defer { try? queue.close() }

        let items = GRDBWorkItemRepository(queue: queue)
        let actions = GRDBActionItemRepository(queue: queue)

        let item = WorkItem(kind: .task, title: "Launch")
        try await items.save(item)

        let first = ActionItem(itemId: item.id, text: "Email the team", sortOrder: 0)
        let second = ActionItem(itemId: item.id, text: "Ask about budget", sortOrder: 1)
        try await actions.save(first)
        try await actions.save(second)

        let listed = await actions.actions(for: item.id)
        #expect(listed.map(\.text) == ["Email the team", "Ask about budget"])

        var done = listed[0]
        done.isDone = true
        done.version += 1
        try await actions.save(done)

        let toggled = await actions.actions(for: item.id)
        #expect(toggled[0].isDone)
        #expect(!toggled[1].isDone)

        try await actions.delete(toggled[0].id)
        let remaining = await actions.actions(for: item.id)
        #expect(remaining.map(\.text) == ["Ask about budget"])
    }
}
