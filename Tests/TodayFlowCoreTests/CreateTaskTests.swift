import Foundation
import Testing
@testable import TodayFlowCore

struct CreateTaskTests {
    private func makeUseCase() -> (CreateTask, InMemoryWorkItemRepository) {
        let repo = InMemoryWorkItemRepository()
        return (CreateTask(repository: repo, calendar: TestDates.workCalendar), repo)
    }

    @Test func defaultsEndAtToTodayEOBAndP3() async throws {
        let (uc, repo) = makeUseCase()
        let start = TestDates.date(2026, 1, 5, hour: 10, minute: 42) // Monday
        let item = try await uc.execute(.init(title: "Review PDF", startAt: start))
        #expect(item.title == "Review PDF")
        #expect(item.priority == .normal) // P3
        #expect(item.startAt == start)
        #expect(item.endAt == TestDates.date(2026, 1, 5, hour: 17)) // 17:00 today
        #expect(item.status == .todo)
        #expect(await repo.item(item.id) != nil) // persisted
    }

    @Test func afterHoursDefaultsToNextBusinessDay() async throws {
        let (uc, _) = makeUseCase()
        let start = TestDates.date(2026, 1, 5, hour: 18, minute: 30) // Monday
        let item = try await uc.execute(.init(title: "Email", startAt: start))
        #expect(item.endAt == TestDates.date(2026, 1, 6, hour: 17)) // Tuesday
    }

    @Test func explicitEndAtIsHonored() async throws {
        let (uc, _) = makeUseCase()
        let start = TestDates.date(2026, 1, 5, hour: 10, minute: 42) // Monday
        let end = TestDates.date(2026, 1, 5, hour: 13, minute: 30)
        let item = try await uc.execute(.init(title: "Standup", startAt: start, endAt: end))
        #expect(item.startAt == start)
        #expect(item.endAt == end)
    }

    @Test func appendsDisplayOrderAfterLastSibling() async throws {
        let (uc, _) = makeUseCase()
        let a = try await uc.execute(.init(title: "A"))
        let b = try await uc.execute(.init(title: "B"))
        let c = try await uc.execute(.init(title: "C"))
        // Each new item sorts strictly after the previous one.
        #expect(FractionalIndex.isLessThan(a.displayOrder, b.displayOrder))
        #expect(FractionalIndex.isLessThan(b.displayOrder, c.displayOrder))
    }

    @Test func emptyTitleThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: CreateTask.Error.emptyTitle) {
            _ = try await uc.execute(.init(title: "   "))
        }
    }

    @Test func longTitleThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: CreateTask.Error.titleTooLong) {
            _ = try await uc.execute(.init(title: String(repeating: "a", count: 201)))
        }
    }

    @Test func invalidParentThrows() async throws {
        let (uc, _) = makeUseCase()
        let task = try await uc.execute(.init(title: "A task"))
        await #expect(throws: CreateTask.Error.invalidParent(kind: .project, parentKind: .task)) {
            _ = try await uc.execute(.init(kind: .project, title: "A project", parentId: task.id))
        }
    }

    @Test func missingParentThrows() async {
        let (uc, _) = makeUseCase()
        await #expect(throws: CreateTask.Error.invalidParent(kind: .task, parentKind: nil)) {
            _ = try await uc.execute(.init(title: "T", parentId: UUIDv7.new()))
        }
    }

    @Test func validParentSucceeds() async throws {
        let (uc, _) = makeUseCase()
        let project = try await uc.execute(.init(kind: .project, title: "P"))
        let task = try await uc.execute(.init(kind: .task, title: "T", parentId: project.id))
        #expect(task.parentId == project.id)
    }
}

@Test func topPlacementInsertsBeforeExistingSiblings() async throws {
    let repo = InMemoryWorkItemRepository()
    let uc = CreateTask(repository: repo, calendar: TestDates.workCalendar)
    let first = try await uc.execute(.init(title: "First"))
    let second = try await uc.execute(.init(title: "Second", placement: .top))

    #expect(FractionalIndex.isLessThan(second.displayOrder, first.displayOrder))
    let children = await repo.children(of: nil)
    #expect(children.first?.title == "Second")
}
