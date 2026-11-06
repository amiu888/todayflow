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
    let settingRepository = InMemorySettingRepository()
    let calendar = WorkCalendar(calendar: testCalendar)
    let now = testNow
    let vm: TodayViewModel

    init(onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil) {
        self.vm = TodayViewModel(
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            settingRepository: settingRepository,
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
func createProject_addsAFilterableProjectWithoutAddingATodayTask() async {
    let f = Fixture()
    await f.vm.load()

    let project = await f.vm.createProject(named: "Website relaunch")

    #expect(project?.kind == .project)
    #expect(project?.title == "Website relaunch")
    #expect(f.vm.projects.map(\.title).contains("Website relaunch"))
    #expect(f.vm.visibleRows.isEmpty)
    #expect(f.vm.progress.total == 0)
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func createProject_rejectsAnEmptyName() async {
    let f = Fixture()
    await f.vm.load()

    let project = await f.vm.createProject(named: "   ")

    #expect(project == nil)
    #expect(f.vm.projects.isEmpty)
    #expect(f.vm.lastError == "Project name can’t be empty.")
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

// MARK: - Sort persistence, selection, manual order (FR-11, FR-12)

@Test @MainActor
func setSort_persistsChoice() async {
    let f = Fixture()
    await f.vm.setSort(.priority)

    #expect(f.vm.sort == .priority)
    #expect(await f.settingRepository.value(for: SettingKeys.todaySort) == "priority")
}

@Test @MainActor
func load_restoresPersistedSort() async {
    let f = Fixture()
    await f.settingRepository.seed("due", for: SettingKeys.todaySort)
    await f.vm.load()

    #expect(f.vm.sort == .due)
}

@Test @MainActor
func load_ignoresUnknownPersistedSort() async {
    let f = Fixture()
    await f.settingRepository.seed("bogus", for: SettingKeys.todaySort)
    await f.vm.load()

    #expect(f.vm.sort == .manual)
}

@Test @MainActor
func select_togglesSelection() async {
    let f = Fixture()
    let alpha = f.item("Alpha", displayOrder: "a0")
    await f.seed(alpha)

    f.vm.select(alpha.id)
    #expect(f.vm.selectedId == alpha.id)

    f.vm.select(alpha.id)
    #expect(f.vm.selectedId == nil)
}

@Test @MainActor
func moveDown_swapsWithNextAndSwitchesToManual() async {
    let f = Fixture()
    let a = f.item("A", priority: .urgent, displayOrder: "a0")
    let b = f.item("B", priority: .high, displayOrder: "a1")
    let c = f.item("C", priority: .normal, displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.vm.load()
    await f.vm.setSort(.priority) // a manual move implies Display order

    await f.vm.moveDown(a.id)

    #expect(f.vm.visibleRows.map(\.title) == ["B", "A", "C"])
    #expect(f.vm.sort == .manual)
    #expect(await f.settingRepository.value(for: SettingKeys.todaySort) == "manual")
    let moved = await f.repository.item(a.id)
    #expect(FractionalIndex.isLessThan(b.displayOrder, moved!.displayOrder))
}

@Test @MainActor
func moveUp_swapsWithPrevious() async {
    let f = Fixture()
    let a = f.item("A", displayOrder: "a0")
    let b = f.item("B", displayOrder: "a1")
    let c = f.item("C", displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.vm.load()

    await f.vm.moveUp(c.id)

    #expect(f.vm.visibleRows.map(\.title) == ["A", "C", "B"])
}

@Test @MainActor
func moveUp_atTopEdge_isNoOp() async {
    let f = Fixture()
    let a = f.item("A", displayOrder: "a0")
    await f.seed(a)
    await f.vm.load()

    await f.vm.moveUp(a.id)

    #expect(f.vm.visibleRows.map(\.title) == ["A"])
    #expect((await f.repository.item(a.id))?.displayOrder == "a0")
}

@Test @MainActor
func dragMove_beforeTarget_placesRowAboveIt() async {
    let f = Fixture()
    let a = f.item("A", displayOrder: "a0")
    let b = f.item("B", displayOrder: "a1")
    let c = f.item("C", displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.vm.load()

    await f.vm.move(c.id, targetId: a.id, before: true)

    #expect(f.vm.visibleRows.map(\.title) == ["C", "A", "B"])
}

@Test @MainActor
func dragMove_afterTarget_placesRowBelowIt() async {
    let f = Fixture()
    let a = f.item("A", displayOrder: "a0")
    let b = f.item("B", displayOrder: "a1")
    let c = f.item("C", displayOrder: "a2")
    await f.seed(a)
    await f.seed(b)
    await f.seed(c)
    await f.vm.load()

    await f.vm.move(a.id, targetId: c.id, before: false)

    #expect(f.vm.visibleRows.map(\.title) == ["B", "C", "A"])
}

@Test @MainActor
func dragMove_keepsParent() async {
    let f = Fixture()
    let project = f.item("Project", kind: .project, displayOrder: "a0")
    let a = f.item("A", displayOrder: "a1", parentId: project.id)
    let b = f.item("B", displayOrder: "a2")
    await f.seed(project)
    await f.seed(a)
    await f.seed(b)
    await f.vm.load()

    await f.vm.move(a.id, targetId: b.id, before: false)

    #expect((await f.repository.item(a.id))?.parentId == project.id)
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

// MARK: - Completion undo (FR-14)

@Test @MainActor
func undoComplete_restoresThePreviousStatus() async {
    let f = Fixture()
    let item = f.item("Ship it", status: .inProgress, displayOrder: "a1")
    await f.seed(item)
    await f.vm.load()

    await f.vm.toggle(item.id)
    #expect(f.vm.completionUndo?.id == item.id)
    #expect(f.vm.completionUndo?.previousStatus == .inProgress)
    #expect(await f.repository.item(item.id)?.status == .done)

    await f.vm.undoComplete()

    let restored = await f.repository.item(item.id)
    #expect(restored?.status == .inProgress)
    #expect(restored?.completedAt == nil)
    #expect(f.vm.completionUndo == nil)
}

@Test @MainActor
func toggle_completingAgainReplacesTheUndoEntry() async {
    let f = Fixture()
    let first = f.item("First", displayOrder: "a1")
    let second = f.item("Second", displayOrder: "a2")
    await f.seed(first)
    await f.seed(second)
    await f.vm.load()

    await f.vm.toggle(first.id)
    await f.vm.toggle(second.id)

    #expect(f.vm.completionUndo?.id == second.id)
}

// MARK: - Project filter (FR-15)

@Test @MainActor
func projectFilter_limitsRowsToTheProjectsAncestry() async {
    let f = Fixture()
    let project = f.item("Website", kind: .project, displayOrder: "a0")
    let task = f.item("Write copy", displayOrder: "a1", parentId: project.id)
    let subtask = f.item("Draft hero", displayOrder: "a2", parentId: task.id)
    let standalone = f.item("Standalone", displayOrder: "a3")
    for item in [project, task, subtask, standalone] { await f.seed(item) }
    await f.vm.load()

    #expect(f.vm.projects.map(\.title) == ["Website"])

    f.vm.projectFilter = project.id
    // The project is a container, not a day task; its tasks and subtasks
    // remain visible through the ancestry filter.
    #expect(Set(f.vm.visibleRows.map(\.title)) == Set(["Write copy", "Draft hero"]))

    f.vm.projectFilter = nil
    #expect(f.vm.visibleRows.count == 3)
    #expect(!f.vm.visibleRows.contains { $0.title == "Website" })
}

// MARK: - Upcoming section (after-hours + tomorrow)

@Test @MainActor
func load_collectsTomorrowAndFutureTasksIntoUpcoming() async {
    let f = Fixture()
    let today = f.item("Today", displayOrder: "a1")
    let tomorrow = f.item(
        "Tomorrow",
        startAt: testCalendar.date(byAdding: .day, value: 1, to: f.now),
        endAt: testCalendar.date(byAdding: .day, value: 1, to: f.calendar.endOfBusiness(for: f.now)),
        displayOrder: "a2"
    )
    let later = f.item(
        "Next week",
        startAt: testCalendar.date(byAdding: .day, value: 10, to: f.now),
        endAt: testCalendar.date(byAdding: .day, value: 10, to: f.calendar.endOfBusiness(for: f.now)),
        displayOrder: "a3"
    )
    let done = f.item("Done", status: .done, displayOrder: "a4")
    for item in [today, tomorrow, later, done] { await f.seed(item) }

    await f.vm.load()

    #expect(f.vm.visibleRows.map(\.title) == ["Today"])
    #expect(f.vm.upcomingRows.map(\.title) == ["Tomorrow"])
}

// MARK: - Due soon (FR-13/FR-14 urgency)

@Test @MainActor
func tasksDueWithinFifteenMinutesAreMarkedDueSoon() async {
    let f = Fixture()
    let soon = f.item(
        "Soon",
        endAt: f.now.addingTimeInterval(10 * 60),
        displayOrder: "a1"
    )
    let later = f.item(
        "Later",
        endAt: f.now.addingTimeInterval(60 * 60),
        displayOrder: "a2"
    )
    await f.seed(soon)
    await f.seed(later)
    await f.vm.load()

    let soonRow = f.vm.visibleRows.first { $0.title == "Soon" }
    let laterRow = f.vm.visibleRows.first { $0.title == "Later" }
    #expect(soonRow?.isDueSoon == true)
    #expect(laterRow?.isDueSoon == false)
}

// MARK: - Day planning / week strip

@Test @MainActor
func selectDay_showsThatDaysPlanAndCanReturnToToday() async {
    let f = Fixture()
    let tomorrow = testCalendar.date(byAdding: .day, value: 1, to: f.now)!
    let task = f.item(
        "Tomorrow task",
        startAt: tomorrow,
        endAt: f.calendar.endOfBusiness(for: tomorrow),
        displayOrder: "a1"
    )
    await f.seed(task)
    await f.vm.load()

    #expect(f.vm.weekDays.count == 7)
    #expect(f.vm.weekDays.first?.isToday == true)

    await f.vm.selectDay(tomorrow)
    #expect(!f.vm.isViewingToday)
    #expect(f.vm.visibleRows.contains { $0.title == "Tomorrow task" })

    await f.vm.goToToday()
    #expect(f.vm.isViewingToday)
}

@Test @MainActor
func setUpcomingPriority_updatesTheTask() async {
    let f = Fixture()
    let tomorrow = testCalendar.date(byAdding: .day, value: 1, to: f.now)!
    let task = f.item(
        "Plan me",
        priority: .low,
        startAt: tomorrow,
        endAt: f.calendar.endOfBusiness(for: tomorrow),
        displayOrder: "a1"
    )
    await f.seed(task)
    await f.vm.load()

    await f.vm.setUpcomingPriority(task.id, .urgent)

    #expect(await f.repository.item(task.id)?.priority == .urgent)
}

// MARK: - Working trays

@Test @MainActor
func trays_startWithAWorkingTrayAndPersistCustomNames() async {
    let f = Fixture()
    await f.vm.load()

    #expect(f.vm.trays.map(\.name) == ["Working tray"])

    let first = f.vm.trays[0].id
    await f.vm.addTray(name: "Now", after: first)
    #expect(f.vm.trays.map(\.name) == ["Working tray", "Now"])

    let now = try! #require(f.vm.trays.last)
    let task = f.item("Focus task", displayOrder: "a1")
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: now.id)

    let column = f.vm.trayColumns.first { $0.tray.id == now.id }
    #expect(column?.items.map(\.title) == ["Focus task"])

    // A fresh model with the same setting store sees the same trays.
    let fresh = TodayViewModel(
        repository: f.repository,
        linkRepository: f.linkRepository,
        attachmentRepository: f.attachmentRepository,
        settingRepository: f.settingRepository,
        calendar: f.calendar,
        clock: { f.now }
    )
    await fresh.load()
    #expect(fresh.trays.map(\.name) == ["Working tray", "Now"])
}

// MARK: - Tray capacity, cross-tray moves, ordering

@Test @MainActor
func trays_supportUnlimitedItemsAndMoveBetweenTrays() async {
    let f = Fixture()
    await f.vm.load()
    let source = f.vm.trays[0].id
    await f.vm.addTray(name: "Dest")

    var items: [WorkItem] = []
    for index in 0..<25 {
        let item = f.item("Tray item \(index)", displayOrder: String(format: "b%02d", index))
        items.append(item)
        await f.seed(item)
    }
    await f.vm.load()

    for item in items {
        await f.vm.addToTray(item.id, trayId: source)
    }

    #expect(f.vm.trayItems(trayId: source).count == 25)

    let destination = try! #require(f.vm.trays.first { $0.name == "Dest" }?.id)
    await f.vm.moveToTray(items[0].id, from: source, to: destination)

    #expect(f.vm.trayItems(trayId: source).count == 24)
    #expect(f.vm.trayItems(trayId: destination).map(\.id) == [items[0].id])

    await f.vm.moveTrayItemUp(items[1].id, trayId: source)
    #expect(f.vm.trayItems(trayId: source).first?.id == items[1].id)

    await f.vm.moveTrayItemDown(items[1].id, trayId: source)
    #expect(f.vm.trayItems(trayId: source).first?.id == items[2].id)
}

// MARK: - Multiple tray drops

@Test @MainActor
func addingMultipleItemsToOneTrayKeepsEveryItem() async {
    let f = Fixture()
    await f.vm.load()
    let trayId = f.vm.trays[0].id

    let first = f.item("First", displayOrder: "a1")
    let second = f.item("Second", displayOrder: "a2")
    await f.seed(first)
    await f.seed(second)
    await f.vm.load()

    await f.vm.addToTray(first.id, trayId: trayId)
    await f.vm.addToTray(second.id, trayId: trayId)

    #expect(f.vm.trayItems(trayId: trayId).map(\.id) == [first.id, second.id])
}

// MARK: - Tray metadata and drop application

@Test @MainActor
func trays_supportRenameColorReorderAndDelete() async {
    let f = Fixture()
    await f.vm.load()
    let first = f.vm.trays[0].id

    await f.vm.renameTray(first, to: "  Client A  ")
    #expect(f.vm.trays.map(\.name) == ["Client A"])

    // Blank names are ignored.
    await f.vm.renameTray(first, to: "   ")
    #expect(f.vm.trays.map(\.name) == ["Client A"])

    await f.vm.setTrayColor(first, colorHex: "#3B82F6")
    #expect(f.vm.trays.first?.colorHex == "#3B82F6")

    await f.vm.addTray(name: "Second")
    let second = try! #require(f.vm.trays.last?.id)
    #expect(f.vm.trays.map(\.name) == ["Client A", "Second"])

    await f.vm.moveTrayLeft(second)
    #expect(f.vm.trays.map(\.name) == ["Second", "Client A"])

    await f.vm.moveTrayRight(second)
    #expect(f.vm.trays.map(\.name) == ["Client A", "Second"])

    await f.vm.deleteTray(second)
    #expect(f.vm.trays.map(\.name) == ["Client A"])
    #expect(f.vm.tray(id: second) == nil)
}

@Test @MainActor
func applyDrop_addsFromTodayAndMovesFromAnotherTray() async {
    let f = Fixture()
    await f.vm.load()
    let source = f.vm.trays[0].id
    await f.vm.addTray(name: "Dest")
    let destination = try! #require(f.vm.trays.first { $0.name == "Dest" }?.id)

    let fromToday = f.item("From Today", displayOrder: "c1")
    let fromTray = f.item("From Tray", displayOrder: "c2")
    await f.seed(fromToday)
    await f.seed(fromTray)
    await f.vm.load()
    await f.vm.addToTray(fromTray.id, trayId: source)

    await f.vm.applyDrop(
        [
            WorkItemDragPayload(itemId: fromToday.id),
            WorkItemDragPayload(itemId: fromTray.id, sourceTrayId: source),
        ],
        to: destination
    )

    #expect(f.vm.trayItems(trayId: source).isEmpty)
    #expect(
        f.vm.trayItems(trayId: destination).map(\.title)
            == ["From Today", "From Tray"]
    )

    // Re-applying the same payloads does not duplicate anything.
    await f.vm.applyDrop(
        [
            WorkItemDragPayload(itemId: fromToday.id),
            WorkItemDragPayload(itemId: fromTray.id, sourceTrayId: source),
        ],
        to: destination
    )
    #expect(f.vm.trayItems(trayId: destination).count == 2)
}

// MARK: - One tray per task

@Test @MainActor
func addingToAnotherTrayMovesTheTask() async {
    let f = Fixture()
    await f.vm.load()
    let first = f.vm.trays[0].id
    await f.vm.addTray(name: "Second")
    let second = try! #require(f.vm.trays.first { $0.name == "Second" }?.id)

    let task = f.item("Only one tray", displayOrder: "d1")
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: first)
    await f.vm.addToTray(task.id, trayId: second)

    #expect(f.vm.trayItems(trayId: first).isEmpty)
    #expect(f.vm.trayItems(trayId: second).map(\.id) == [task.id])
}

@Test @MainActor
func moveToTrayRemovesTheTaskFromEveryOtherTray() async {
    let f = Fixture()
    await f.vm.load()
    let first = f.vm.trays[0].id
    await f.vm.addTray(name: "Second")
    await f.vm.addTray(name: "Third")
    let second = try! #require(f.vm.trays.first { $0.name == "Second" }?.id)
    let third = try! #require(f.vm.trays.first { $0.name == "Third" }?.id)

    let task = f.item("One home", displayOrder: "d2")
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: first)
    await f.vm.addToTray(task.id, trayId: third)
    await f.vm.moveToTray(task.id, from: first, to: second)

    #expect(f.vm.trayItems(trayId: first).isEmpty)
    #expect(f.vm.trayItems(trayId: third).isEmpty)
    #expect(f.vm.trayItems(trayId: second).map(\.id) == [task.id])
}

// MARK: - Tray workflows

@Test @MainActor
func workflowMovesCompletedTaskToTargetTray() async throws {
    let f = Fixture()
    await f.vm.load()
    await f.vm.addTray(name: "Done")
    let source = f.vm.trays[0]
    let target = try #require(f.vm.trays.last)
    let task = f.item("Finish report", displayOrder: "a1")
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: source.id)

    let rule = TrayWorkflowRule(
        sourceTrayId: source.id,
        targetTrayId: target.id,
        trigger: .completed
    )
    let data = try JSONEncoder().encode([rule])
    try await f.settingRepository.set(
        String(decoding: data, as: UTF8.self),
        for: SettingKeys.workflowRules
    )

    await f.vm.toggle(task.id)

    #expect(f.vm.tray(id: source.id)?.itemIds.isEmpty == true)
    #expect(f.vm.tray(id: target.id)?.itemIds == [task.id])
    #expect(f.vm.trayColumns.first { $0.tray.id == target.id }?.items.map(\.id) == [task.id])
}

@Test @MainActor
func workflowMovesOverdueTaskToTargetTray() async throws {
    let f = Fixture()
    await f.vm.load()
    await f.vm.addTray(name: "Overdue")
    let source = f.vm.trays[0]
    let target = try #require(f.vm.trays.last)
    let task = f.item(
        "Late invoice",
        endAt: f.now.addingTimeInterval(-3600),
        displayOrder: "a1"
    )
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: source.id)

    let rule = TrayWorkflowRule(
        sourceTrayId: source.id,
        targetTrayId: target.id,
        trigger: .dueReached
    )
    let data = try JSONEncoder().encode([rule])
    try await f.settingRepository.set(
        String(decoding: data, as: UTF8.self),
        for: SettingKeys.workflowRules
    )

    await f.vm.runWorkflows(now: f.now)

    #expect(f.vm.tray(id: source.id)?.itemIds.isEmpty == true)
    #expect(f.vm.tray(id: target.id)?.itemIds == [task.id])
}

@Test @MainActor
func disabledWorkflowDoesNotMoveTasks() async throws {
    let f = Fixture()
    await f.vm.load()
    await f.vm.addTray(name: "Done")
    let source = f.vm.trays[0]
    let target = try #require(f.vm.trays.last)
    let task = f.item("Stay put", status: .done, displayOrder: "a1")
    await f.seed(task)
    await f.vm.load()
    await f.vm.addToTray(task.id, trayId: source.id)

    let rule = TrayWorkflowRule(
        sourceTrayId: source.id,
        targetTrayId: target.id,
        trigger: .completed,
        isEnabled: false
    )
    let data = try JSONEncoder().encode([rule])
    try await f.settingRepository.set(
        String(decoding: data, as: UTF8.self),
        for: SettingKeys.workflowRules
    )
    await f.vm.runWorkflows(now: f.now)

    #expect(f.vm.tray(id: source.id)?.itemIds == [task.id])
    #expect(f.vm.tray(id: target.id)?.itemIds.isEmpty == true)
}
