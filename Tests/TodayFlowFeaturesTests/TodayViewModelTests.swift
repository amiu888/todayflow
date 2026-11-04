import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

// MARK: - Deterministic clock / calendar

/// All date math in these tests is UTC.
private let testCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Fixed "now": Tuesday 2026-11-03, 10:00 UTC.
/// WorkCalendar is 09:00–17:00 Mon–Fri, so EOB is 17:00 UTC the same day.
private let testNow: Date = {
    testCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 0, second: 0)
    )!
}()

// MARK: - Fixture

@MainActor
private struct Fixture {
    let repository = InMemoryWorkItemRepository()
    let linkRepository = InMemoryLinkRepository()
    let attachmentRepository = InMemoryAttachmentRepository()
    let calendar = WorkCalendar(calendar: testCalendar)
    let now = testNow
    let vm: TodayViewModel

    init(onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil) {
        self.vm = TodayViewModel(
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            calendar: calendar,
            clock: { testNow },
            onOpenTask: onOpenTask
        )
    }

    func item(
        _ title: String,
        kind: WorkItem.Kind = .task,
        status: Status = .todo,
        priority: Priority = .normal,
        startAt: Date? = nil,
        endAt: Date? = nil,
        displayOrder: String,
        parentId: UUIDv7? = nil,
        descriptionMd: String = "",
        color: String? = nil,
        completedAt: Date? = nil
    ) -> WorkItem {
        WorkItem(
            kind: kind,
            title: title,
            parentId: parentId,
            descriptionMd: descriptionMd,
            status: status,
            priority: priority,
            startAt: startAt ?? now.addingTimeInterval(-3_600),
            endAt: endAt ?? calendar.endOfBusiness(for: now),
            completedAt: completedAt,
            displayOrder: displayOrder,
            color: color
        )
    }

    func seed(_ item: WorkItem) async { await repository.seed(item) }
    func seedLink(_ link: ItemLink) async { await linkRepository.seed(link) }
    func seedAttachment(_ attachment: TodayFlowCore.Attachment) async {
        await attachmentRepository.seed(attachment)
    }
}

/// Records which ids the `onOpenTask` hook received.
@MainActor
private final class OpenLog {
    private(set) var opened: [UUIDv7] = []
    func record(_ id: UUIDv7) { opened.append(id) }
}

/// Polls `condition` (up to ~5 s) and fails the test if it never holds.
@MainActor
private func expectEventually(
    _ condition: @MainActor () async -> Bool
) async {
    for _ in 0..<200 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(25))
    }
    #expect(await condition(), "condition was not met within the timeout")
}

// MARK: - Loading

@Test @MainActor
func load_mapsOpenItemsInDisplayOrder() async {
    let f = Fixture()
    await f.seed(f.item("Alpha", displayOrder: "a0"))
    await f.seed(f.item("Beta", displayOrder: "a1"))
    await f.seed(f.item("Gamma", displayOrder: "a2"))
    await f.vm.load()

    #expect(f.vm.visibleRows.map(\.title) == ["Alpha", "Beta", "Gamma"])
    #expect(f.vm.progress.total == 3)
    #expect(f.vm.progress.done == 0)
    #expect(f.vm.progress.remaining == 3)
    #expect(!f.vm.progress.isCleared)
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func load_pinsOverdueOnTop() async {
    let f = Fixture()
    await f.seed(f.item("OnTime", displayOrder: "a0"))
    await f.seed(f.item("Late", endAt: f.now.addingTimeInterval(-1_800), displayOrder: "a1"))
    await f.vm.load()

    #expect(f.vm.visibleRows.map(\.title) == ["Late", "OnTime"])
    #expect(f.vm.visibleOverdueRows.map(\.title) == ["Late"])
    #expect(f.vm.visibleOpenRows.map(\.title) == ["OnTime"])
    #expect(f.vm.progress.overdue == 1)
}

@Test @MainActor
func load_computesProgressIncludingDoneToday() async {
    let f = Fixture()
    await f.seed(f.item("Open1", displayOrder: "a0"))
    await f.seed(f.item("Open2", displayOrder: "a1"))
    await f.seed(f.item("Finished", status: .done, displayOrder: "a2", completedAt: f.now))
    await f.vm.load()

    #expect(f.vm.progress.done == 1)
    #expect(f.vm.progress.total == 3)
    #expect(f.vm.progress.remaining == 2)
    #expect(f.vm.visibleDoneRows.map(\.title) == ["Finished"])
    #expect(f.vm.visibleRows.count == 2)
}

@Test @MainActor
func load_emptyDay() async {
    let f = Fixture()
    await f.vm.load()

    #expect(f.vm.visibleRows.isEmpty)
    #expect(f.vm.visibleDoneRows.isEmpty)
    #expect(f.vm.progress.total == 0)
    #expect(!f.vm.progress.isCleared)
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func progress_countsTimeUntilEndOfBusiness() async {
    let f = Fixture() // 10:00 UTC, EOB 17:00 UTC
    await f.seed(f.item("Alpha", displayOrder: "a0"))
    await f.vm.load()

    #expect(f.vm.progress.secondsUntilEOB == 25_200)
}

// MARK: - Toggle

@Test @MainActor
func toggle_completesThenReopens() async {
    let f = Fixture()
    let alpha = f.item("Alpha", displayOrder: "a0")
    await f.seed(alpha)
    await f.vm.load()
    #expect(f.vm.visibleRows.first?.isDone == false)

    await f.vm.toggle(alpha.id)
    #expect(f.vm.visibleRows.isEmpty)
    #expect(f.vm.visibleDoneRows.map(\.title) == ["Alpha"])
    #expect(f.vm.progress.isCleared)
    let doneItem = await f.repository.item(alpha.id)
    #expect(doneItem?.status == .done)
    #expect(doneItem?.completedAt == f.now)

    await f.vm.toggle(alpha.id)
    let reopened = await f.repository.item(alpha.id)
    #expect(reopened?.status == .todo)
    #expect(reopened?.completedAt == nil)
    #expect(f.vm.visibleRows.map(\.title) == ["Alpha"])
}

// MARK: - Quick actions

@Test @MainActor
func quickAction_setPriority_persistsAndIgnoresNoop() async {
    let f = Fixture()
    let alpha = f.item("Alpha", priority: .normal, displayOrder: "a0")
    await f.seed(alpha)
    await f.vm.load()

    await f.vm.quickAction(alpha.id, .setPriority(.urgent))
    #expect((await f.repository.item(alpha.id))?.priority == .urgent)
    #expect(f.vm.lastError == nil)

    await f.vm.quickAction(alpha.id, .setPriority(.urgent)) // no-op, not an error
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func quickAction_moveToTomorrow_reschedulesToNextWorkingDay() async {
    let f = Fixture() // Tuesday
    let alpha = f.item("Alpha", endAt: f.now.addingTimeInterval(-600), displayOrder: "a0")
    await f.seed(alpha)
    await f.vm.load()
    #expect(f.vm.visibleRows.first?.isOverdue == true)

    await f.vm.quickAction(alpha.id, .moveToTomorrow)

    let expected = MoveToTomorrow(repository: f.repository, calendar: f.calendar)
        .nextWorkingDayEOB(after: f.now)
    let saved = await f.repository.item(alpha.id)
    #expect(saved?.endAt == expected)
    #expect(f.vm.lastError == nil)
    #expect(f.vm.visibleRows.first?.isOverdue == false)
}

@Test @MainActor
func quickAction_open_invokesHook() async {
    let log = OpenLog()
    let f = Fixture(onOpenTask: { log.record($0) })
    let alpha = f.item("Alpha", displayOrder: "a0")
    await f.seed(alpha)
    await f.vm.load()

    await f.vm.quickAction(alpha.id, .open)
    #expect(log.opened == [alpha.id])
}

// MARK: - Blocked derivation

@Test @MainActor
func blockedPrerequisite_showsLockThenClears() async {
    let f = Fixture()
    let prereq = f.item("Prereq", displayOrder: "a0")
    let dependent = f.item("Dependent", displayOrder: "a1")
    await f.seed(prereq)
    await f.seed(dependent)
    await f.seedLink(ItemLink(fromId: prereq.id, toId: dependent.id, kind: .blocks))
    await f.vm.load()

    #expect(f.vm.visibleRows.first { $0.id == prereq.id }?.isBlocked == false)
    #expect(f.vm.visibleRows.first { $0.id == dependent.id }?.isBlocked == true)

    await f.vm.toggle(prereq.id)
    #expect(f.vm.visibleRows.first { $0.id == dependent.id }?.isBlocked == false)
}

@Test @MainActor
func blockedByPrerequisiteOutsideToday() async {
    let f = Fixture()
    let future = f.item(
        "FuturePrereq",
        startAt: f.now.addingTimeInterval(86_400),
        endAt: f.now.addingTimeInterval(86_400 + 3_600),
        displayOrder: "a0"
    )
    let dependent = f.item("Dependent", displayOrder: "a1")
    await f.seed(future)
    await f.seed(dependent)
    await f.seedLink(ItemLink(fromId: future.id, toId: dependent.id, kind: .blocks))
    await f.vm.load()

    #expect(f.vm.visibleRows.first { $0.id == dependent.id }?.isBlocked == true)
}

// MARK: - Filter, search, sort

@Test @MainActor
func filterBlocked_showsOnlyLockedRows() async {
    let f = Fixture()
    let free = f.item("Free", displayOrder: "a0")
    let locked = f.item("Locked", displayOrder: "a1")
    let other = f.item("Other", displayOrder: "a2")
    await f.seed(free)
    await f.seed(locked)
    await f.seed(other)
    await f.seedLink(ItemLink(fromId: free.id, toId: locked.id, kind: .blocks))
    await f.vm.load()

    f.vm.filter = .blocked
    #expect(f.vm.visibleRows.map(\.title) == ["Locked"])
}

@Test @MainActor
func filterP1P2_showsUrgentAndHigh() async {
    let f = Fixture()
    await f.seed(f.item("Urgent", priority: .urgent, displayOrder: "a0"))
    await f.seed(f.item("High", priority: .high, displayOrder: "a1"))
    await f.seed(f.item("Normal", priority: .normal, displayOrder: "a2"))
    await f.vm.load()

    f.vm.filter = .p1p2
    #expect(f.vm.visibleRows.map(\.title) == ["Urgent", "High"])
}

@Test @MainActor
func search_matchesTitleDescriptionAndAttachmentName() async {
    let f = Fixture()
    let a = f.item("Review PR", displayOrder: "a0")
    let b = f.item("Ship it", displayOrder: "a1", descriptionMd: "quarterly numbers")
    let c = f.item("Misc", displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.seedAttachment(
        TodayFlowCore.Attachment(itemId: c.id, kind: .file, displayName: "budget.pdf")
    )
    await f.vm.load()

    f.vm.searchText = "review"
    #expect(f.vm.visibleRows.map(\.title) == ["Review PR"])
    f.vm.searchText = "quarterly"
    #expect(f.vm.visibleRows.map(\.title) == ["Ship it"])
    f.vm.searchText = "budget"
    #expect(f.vm.visibleRows.map(\.title) == ["Misc"])
    f.vm.searchText = "zzz"
    #expect(f.vm.visibleRows.isEmpty)
}

@Test @MainActor
func sortPriority_ordersUrgentFirst() async {
    let f = Fixture()
    await f.seed(f.item("Normal", priority: .normal, displayOrder: "a0"))
    await f.seed(f.item("Urgent", priority: .urgent, displayOrder: "a1"))
    await f.seed(f.item("High", priority: .high, displayOrder: "a2"))
    await f.vm.load()

    f.vm.sort = .priority
    #expect(f.vm.visibleRows.map(\.title) == ["Urgent", "High", "Normal"])
}

@Test @MainActor
func sortDue_ordersByDueDateThenPriority() async {
    let f = Fixture()
    let midday = f.now.addingTimeInterval(3_600)
    let afternoon = f.now.addingTimeInterval(7_200)
    await f.seed(f.item("EarlyUrgent", priority: .urgent, endAt: midday, displayOrder: "a0"))
    await f.seed(f.item("LateHigh", priority: .high, endAt: afternoon, displayOrder: "a1"))
    await f.seed(f.item("EarlyNormal", priority: .normal, endAt: midday, displayOrder: "a2"))
    await f.vm.load()

    f.vm.sort = .due
    #expect(f.vm.visibleRows.map(\.title) == ["EarlyUrgent", "EarlyNormal", "LateHigh"])
}

// MARK: - Chain, parent color, attachments

@Test @MainActor
func chainConnector_drawnForAdjacentBlockedPair() async {
    let f = Fixture()
    let a = f.item("First", displayOrder: "a0")
    let b = f.item("Second", displayOrder: "a1")
    let c = f.item("Third", displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.seedLink(ItemLink(fromId: a.id, toId: b.id, kind: .blocks))
    await f.vm.load()

    #expect(f.vm.visibleRows.map(\.hasChainBelow) == [true, false, false])
}

@Test @MainActor
func parentColor_stripFromParentOutsideList() async {
    let f = Fixture()
    let project = f.item(
        "Website",
        kind: .project,
        startAt: f.now.addingTimeInterval(86_400 * 30),
        endAt: f.now.addingTimeInterval(86_400 * 60),
        displayOrder: "a0",
        color: "#ff0000"
    )
    let child = f.item("Landing page", displayOrder: "a1", parentId: project.id)
    await f.seed(project)
    await f.seed(child)
    await f.vm.load()

    #expect(f.vm.visibleRows.first { $0.id == child.id }?.parentColorHex == "#ff0000")
}

@Test @MainActor
func attachmentHints_capAtThreeButCountAll() async throws {
    let f = Fixture()
    let a = f.item("Docs", displayOrder: "a0")
    await f.seed(a)
    for index in 1...5 {
        await f.seedAttachment(
            TodayFlowCore.Attachment(itemId: a.id, kind: .file, displayName: "doc\(index).txt")
        )
    }
    await f.vm.load()

    let row = try #require(f.vm.visibleRows.first)
    #expect(row.attachments.count == 3)
    #expect(row.attachmentCount == 5)
}

// MARK: - Live updates

@Test @MainActor
func observe_reactsToExternalSaves() async throws {
    let f = Fixture()
    let alpha = f.item("Alpha", displayOrder: "a0")
    await f.seed(alpha)

    let task = Task { await f.vm.observe() }
    await expectEventually { f.vm.progress.total == 1 }

    var edited = alpha
    edited.title = "Alpha (edited)"
    try await f.repository.save(edited)

    await expectEventually { f.vm.visibleRows.first?.title == "Alpha (edited)" }
    task.cancel()
}
