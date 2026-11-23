import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowFeatures

@MainActor
struct QuickFindModelTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)

    private func make(_ items: [WorkItem], recent: [UUIDv7] = []) async -> (QuickFindModel, InMemoryWorkItemRepository) {
        let repository = InMemoryWorkItemRepository()
        for item in items { await repository.seed(item) }
        let fixedNow = now
        let model = QuickFindModel(
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            clock: { fixedNow },
            recent: { recent }
        )
        await model.load()
        return (model, repository)
    }

    private func task(_ title: String, tags: [String] = [], dueIn: Double = 86_400) -> WorkItem {
        WorkItem(title: title, startAt: now, endAt: now.addingTimeInterval(dueIn), tags: tags, createdAt: now, updatedAt: now)
    }

    @Test func typingFindsAndArrowKeysMoveTheSelection() async {
        let (model, _) = await make([task("Patch db server"), task("Patch web server"), task("Lunch")])
        model.text = "patch"
        #expect(model.results.count == 2)
        #expect(model.selection == 0)
        model.move(1)
        #expect(model.selection == 1)
        model.move(5) // the Ask row is not wired, so it stops at the last task
        #expect(model.selection == 1)
        model.move(-9)
        #expect(model.selection == 0)
    }

    @Test func returnOpensTheTaskAndCloses() async {
        let item = task("Patch db server")
        let (model, _) = await make([item])
        var opened: UUIDv7?
        var closed = false
        model.onOpen = { opened = $0 }
        model.onClose = { closed = true }
        model.text = "patch"
        model.activate()
        #expect(opened == item.id)
        #expect(closed)
    }

    @Test func theAskRowSendsTheWords() async {
        let (model, _) = await make([task("Patch db server")])
        var asked: String?
        model.onAsk = { asked = $0 }
        model.text = "the java thing from last week"
        #expect(model.results.isEmpty)
        #expect(model.showsAskRow)
        model.activate()
        #expect(asked == "the java thing from last week")
    }

    @Test func hashOffersTagCompletions() async {
        let (model, _) = await make([task("A", tags: ["billing", "db-server-01"]), task("B", tags: ["billing"])])
        model.text = "patch #bi"
        #expect(model.completions.map(\.label) == ["#billing"])
        model.complete(model.completions[0])
        #expect(model.text == "patch #billing ")
    }

    @Test func commandReturnCompletesAndOptionReturnMovesToToday() async {
        let later = task("Later thing", dueIn: 5 * 86_400)
        let other = WorkItem(
            title: "Next week thing", startAt: now.addingTimeInterval(6 * 86_400),
            endAt: now.addingTimeInterval(7 * 86_400), createdAt: now, updatedAt: now
        )
        let (model, repository) = await make([later, other])

        model.text = "later"
        await model.completeSelected()
        #expect(await repository.item(later.id)?.status == .done)

        model.text = "next week"
        await model.doTodaySelected()
        let moved = await repository.item(other.id)
        #expect(moved?.startAt == now)
        #expect(moved?.endAt == other.endAt) // a later due date is kept
    }

    @Test func emptySearchShowsRecentTasks() async {
        let viewed = task("Viewed yesterday", dueIn: 30 * 86_400)
        let (model, _) = await make([viewed, task("Never opened", dueIn: 30 * 86_400)], recent: [viewed.id])
        #expect(model.results.map(\.item.title) == ["Viewed yesterday"])
    }
}
