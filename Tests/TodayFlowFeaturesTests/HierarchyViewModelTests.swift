import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

// MARK: - Deterministic clock / calendar

/// All date math in these tests is UTC.
private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Fixed "now": Tuesday 2026-11-03, 10:00 UTC.
private let testNow: Date = {
    testCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 0, second: 0)
    )!
}()

// MARK: - Fixture

/// Wires a `HierarchyViewModel` to in-memory repositories with the pinned
/// calendar and clock, so every date the model writes is deterministic.
@MainActor
private struct Fixture {
    let repository: InMemoryWorkItemRepository
    let linkRepository: InMemoryLinkRepository
    let vm: HierarchyViewModel

    init() {
        let repository = InMemoryWorkItemRepository()
        let linkRepository = InMemoryLinkRepository()
        self.repository = repository
        self.linkRepository = linkRepository
        vm = HierarchyViewModel(
            repository: repository,
            linkRepository: linkRepository,
            calendar: WorkCalendar(calendar: testCalendar),
            clock: { testNow }
        )
    }
}

// MARK: - Tree building

@Test @MainActor
func refresh_buildsTreeFromAllItems() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "Epic", displayOrder: "a")
    let p1 = WorkItem(kind: .project, title: "P1", parentId: epic.id, displayOrder: "b")
    let p2 = WorkItem(kind: .project, title: "P2", parentId: epic.id, displayOrder: "c")
    let t1 = WorkItem(title: "T1", parentId: p1.id, displayOrder: "d")
    for item in [epic, p1, p2, t1] {
        await f.repository.seed(item)
    }

    await f.vm.refresh()

    #expect(f.vm.nodes.count == 1)
    #expect(f.vm.nodes[0].id == epic.id)
    #expect(f.vm.nodes[0].children.map(\.item.title) == ["P1", "P2"])
    #expect(f.vm.nodes[0].children[0].children.map(\.item.title) == ["T1"])
}

@Test @MainActor
func refresh_orphansFloatToTopLevel() async {
    let f = Fixture()
    let project = WorkItem(
        kind: .project,
        title: "P",
        parentId: UUIDv7.new(), // a stale reference to a missing parent
        displayOrder: "a"
    )
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "b")
    await f.repository.seed(project)
    await f.repository.seed(task)

    await f.vm.refresh()

    #expect(f.vm.nodes.count == 1)
    #expect(f.vm.nodes[0].id == project.id)
    #expect(f.vm.nodes[0].item.parentId == nil)
    #expect(f.vm.nodes[0].children.map(\.id) == [task.id])
}

@Test @MainActor
func refresh_sortsSiblingsByDisplayOrder() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "0")
    let c = WorkItem(title: "C", parentId: project.id, displayOrder: "c")
    let a = WorkItem(title: "A", parentId: project.id, displayOrder: "a")
    let b = WorkItem(title: "B", parentId: project.id, displayOrder: "b")
    // Seed out of order: the tree must sort, not append.
    for item in [project, c, a, b] {
        await f.repository.seed(item)
    }

    await f.vm.refresh()

    #expect(f.vm.nodes[0].children.map(\.item.title) == ["A", "B", "C"])
}

@Test @MainActor
func refresh_attachesRolledUpProgress() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "e")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "a")
    let t1 = WorkItem(
        title: "T1", parentId: project.id,
        status: .done, completedAt: testNow, displayOrder: "b"
    )
    let t2 = WorkItem(title: "T2", parentId: project.id, displayOrder: "c")
    let t3 = WorkItem(title: "T3", parentId: project.id, displayOrder: "d")
    for item in [epic, project, t1, t2, t3] {
        await f.repository.seed(item)
    }

    await f.vm.refresh()

    let projectNode = f.vm.nodes[0].children[0]
    #expect(projectNode.progress.done == 1)
    #expect(projectNode.progress.total == 3)
    #expect(f.vm.nodes[0].progress.done == 1)
    #expect(f.vm.nodes[0].progress.total == 3)
}

@Test @MainActor
func firstLoad_expandsAllContainers() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "b")
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "c")
    for item in [epic, project, task] {
        await f.repository.seed(item)
    }

    await f.vm.refresh()

    #expect(f.vm.expanded.contains(epic.id))
    #expect(f.vm.expanded.contains(project.id))
    #expect(!f.vm.expanded.contains(task.id))
}

@Test @MainActor
func refresh_preservesExpansion() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "b")
    // A task under the project makes it a container, so it is expanded too.
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "c")
    for item in [epic, project, task] {
        await f.repository.seed(item)
    }

    await f.vm.refresh()
    f.vm.toggle(epic.id)
    await f.vm.refresh()

    #expect(!f.vm.expanded.contains(epic.id))
    #expect(f.vm.expanded.contains(project.id))
}

// MARK: - Actions (driver.md §2 hierarchy rules)

@Test @MainActor
func addChild_underEpic_createsProject() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    await f.repository.seed(epic)
    await f.vm.refresh()

    let created = await f.vm.addChild(to: epic.id, kind: .project, title: "New Project")

    #expect(created != nil)
    #expect(created?.kind == .project)
    #expect(created?.parentId == epic.id)
    #expect(f.vm.lastError == nil)
    #expect(f.vm.nodes[0].children.map(\.item.title) == ["New Project"])
}

@Test @MainActor
func addChild_invalidKind_reportsError() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    await f.repository.seed(epic)
    await f.vm.refresh()

    let created = await f.vm.addChild(to: epic.id, kind: .task, title: "T")

    #expect(created == nil)
    #expect(f.vm.lastError != nil)
    #expect((await f.repository.allItems()).count == 1)
}

@Test @MainActor
func reparent_valid() async {
    let f = Fixture()
    let a = WorkItem(kind: .project, title: "A", displayOrder: "a")
    let b = WorkItem(kind: .project, title: "B", displayOrder: "b")
    let task = WorkItem(title: "T", parentId: a.id, displayOrder: "c")
    for item in [a, b, task] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.reparent(task.id, toParent: b.id)

    #expect(f.vm.lastError == nil)
    #expect((await f.repository.item(task.id))?.parentId == b.id)
}

@Test @MainActor
func reparent_invalidKind_reportsError() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", displayOrder: "b")
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "c")
    for item in [epic, project, task] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.reparent(task.id, toParent: epic.id)

    #expect(f.vm.lastError != nil)
    #expect((await f.repository.item(task.id))?.parentId == project.id)
}

@Test @MainActor
func reparent_ontoOwnDescendantOrSelf_rejected() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "a")
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "b")
    await f.repository.seed(project)
    await f.repository.seed(task)
    await f.vm.refresh()

    await f.vm.reparent(project.id, toParent: task.id)
    #expect(f.vm.lastError != nil)
    #expect((await f.repository.item(project.id))?.parentId == nil) // unchanged

    await f.vm.reparent(project.id, toParent: project.id)
    #expect(f.vm.lastError != nil)
}

@Test @MainActor
func moveUp_swapsWithPreviousSibling() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "0")
    let a = WorkItem(title: "A", parentId: project.id, displayOrder: "a")
    let b = WorkItem(title: "B", parentId: project.id, displayOrder: "b")
    let c = WorkItem(title: "C", parentId: project.id, displayOrder: "c")
    for item in [project, a, b, c] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.moveUp(b.id)

    #expect(f.vm.lastError == nil)
    #expect((await f.repository.children(of: project.id)).map(\.title) == ["B", "A", "C"])
}

@Test @MainActor
func moveDown_swapsWithNextSibling() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "0")
    let a = WorkItem(title: "A", parentId: project.id, displayOrder: "a")
    let b = WorkItem(title: "B", parentId: project.id, displayOrder: "b")
    let c = WorkItem(title: "C", parentId: project.id, displayOrder: "c")
    for item in [project, a, b, c] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.moveDown(a.id)

    #expect(f.vm.lastError == nil)
    #expect((await f.repository.children(of: project.id)).map(\.title) == ["B", "A", "C"])
}

@Test @MainActor
func delete_unparentsChildren() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "a")
    let t1 = WorkItem(title: "T1", parentId: project.id, displayOrder: "b")
    let t2 = WorkItem(title: "T2", parentId: project.id, displayOrder: "c")
    for item in [project, t1, t2] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.delete(project.id)

    #expect(f.vm.lastError == nil)
    #expect(await f.repository.item(project.id) == nil)
    #expect((await f.repository.item(t1.id))?.parentId == nil)
    #expect((await f.repository.item(t2.id))?.parentId == nil)
    #expect(f.vm.nodes.map(\.item.title) == ["T1", "T2"])
}

@Test @MainActor
func deleteWithChildren_removesSubtree() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "b")
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "c")
    for item in [epic, project, task] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    await f.vm.delete(epic.id, withChildren: true)

    #expect(f.vm.lastError == nil)
    #expect((await f.repository.allItems()).isEmpty)
    #expect(f.vm.nodes.isEmpty)
}

@Test @MainActor
func complete_marksDoneAndUpdatesProgress() async {
    let f = Fixture()
    let project = WorkItem(kind: .project, title: "P", displayOrder: "a")
    let t1 = WorkItem(title: "T1", parentId: project.id, displayOrder: "b")
    let t2 = WorkItem(title: "T2", parentId: project.id, displayOrder: "c")
    for item in [project, t1, t2] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    // `nodes[0]` is the project (no epic in this tree); the roll-up lives on it.
    #expect(f.vm.nodes[0].progress.done == 0)
    #expect(f.vm.nodes[0].progress.total == 2)

    await f.vm.complete(t1.id)

    #expect(f.vm.lastError == nil)
    #expect((await f.repository.item(t1.id))?.status == .done)
    #expect(f.vm.nodes[0].progress.done == 1)
    #expect(f.vm.nodes[0].progress.total == 2)
}

// MARK: - Flattened rows

@Test @MainActor
func visibleRows_respectsExpansion() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "b")
    let task = WorkItem(title: "T", parentId: project.id, displayOrder: "c")
    for item in [epic, project, task] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    #expect(f.vm.visibleRows.map(\.node.item.title) == ["E", "P", "T"])
    #expect(f.vm.visibleRows.map(\.depth) == [0, 1, 2])

    f.vm.toggle(epic.id)

    #expect(f.vm.visibleRows.map(\.node.item.title) == ["E"])
}

@Test @MainActor
func toggle_expandsAndCollapses() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "E", displayOrder: "a")
    let project = WorkItem(kind: .project, title: "P", parentId: epic.id, displayOrder: "b")
    for item in [epic, project] {
        await f.repository.seed(item)
    }
    await f.vm.refresh()

    #expect(f.vm.expanded.contains(epic.id))
    f.vm.toggle(epic.id)
    #expect(!f.vm.expanded.contains(epic.id))
    f.vm.toggle(epic.id)
    #expect(f.vm.expanded.contains(epic.id))
}
