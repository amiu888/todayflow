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
/// WorkCalendar is 09:00–17:00 Mon–Fri, so EOB is 17:00 UTC the same day.
private let testNow: Date = {
    testCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 3, hour: 10, minute: 0, second: 0)
    )!
}()

/// Builds a UTC date for the assertions.
private func date(
    _ year: Int, _ month: Int, _ day: Int,
    hour: Int = 0, minute: Int = 0, second: Int = 0
) -> Date {
    testCalendar.date(
        from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
    )!
}

// MARK: - Fixture

/// Wires a `DetailViewModel` to in-memory repositories with the pinned
/// calendar and clock, so every date the model writes is deterministic.
@MainActor
private struct Fixture {
    let repository: InMemoryWorkItemRepository
    let linkRepository: InMemoryLinkRepository
    let attachmentRepository: InMemoryAttachmentRepository
    let activityRepository = InMemoryActivityRepository()
    let vm: DetailViewModel

    init(
        itemId: UUIDv7,
        onClosed: (@MainActor () -> Void)? = nil
    ) {
        let repository = InMemoryWorkItemRepository()
        let linkRepository = InMemoryLinkRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        self.repository = repository
        self.linkRepository = linkRepository
        self.attachmentRepository = attachmentRepository
        vm = DetailViewModel(
            itemId: itemId,
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            activityRepository: activityRepository,
            calendar: WorkCalendar(calendar: testCalendar),
            clock: { testNow },
            onClosed: onClosed
        )
    }
}

/// Records how many times the VM's `onClosed` hook fires.
@MainActor
private final class ClosedLog {
    private(set) var count = 0
    func record() { count += 1 }
}

// MARK: - Loading

@Test @MainActor
func load_populatesAllSections() async {
    let project = WorkItem(kind: .project, title: "Website")
    let item = WorkItem(
        kind: .task,
        title: "Review contract",
        parentId: project.id,
        descriptionMd: "Check the scope.",
        status: .inProgress,
        priority: .high,
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let subtask = WorkItem(
        kind: .subtask, title: "Check scope",
        parentId: item.id, status: .done,
        completedAt: date(2026, 11, 2, hour: 15)
    )
    let prerequisite = WorkItem(kind: .task, title: "Sign NDA", status: .inProgress)
    let related = WorkItem(kind: .task, title: "Design review")
    let attachment = Attachment(itemId: item.id, kind: .file, displayName: "contract.pdf")

    let f = Fixture(itemId: item.id)
    await f.repository.seed(project)
    await f.repository.seed(item)
    await f.repository.seed(subtask)
    await f.repository.seed(prerequisite)
    await f.repository.seed(related)
    await f.linkRepository.seed(ItemLink(fromId: prerequisite.id, toId: item.id))
    await f.linkRepository.seed(ItemLink(fromId: related.id, toId: item.id, kind: .relatesTo))
    await f.attachmentRepository.seed(attachment)

    await f.vm.load()

    #expect(f.vm.item?.title == "Review contract")
    #expect(f.vm.edit.title == "Review contract")
    #expect(f.vm.edit.descriptionMd == "Check the scope.")
    #expect(f.vm.edit.startAt == date(2026, 11, 3, hour: 9))
    #expect(f.vm.edit.endAt == date(2026, 11, 3, hour: 17))
    #expect(f.vm.status == .inProgress)
    #expect(f.vm.displayStatus == .blocked, "an open prerequisite must show as blocked")
    #expect(f.vm.priority == .high)
    #expect(f.vm.parent?.id == project.id)
    #expect(f.vm.children.map(\.id) == [subtask.id])
    #expect(f.vm.blockers.map(\.id) == [prerequisite.id])
    #expect(f.vm.related.map(\.id) == [related.id])
    #expect(f.vm.attachments.map(\.displayName) == ["contract.pdf"])
    #expect(f.vm.progress == RollUpProgress.Result(done: 0, total: 1, fraction: 0))
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func load_missingItem_leavesItemNil() async {
    let f = Fixture(itemId: UUIDv7.new())
    await f.vm.load()
    #expect(f.vm.item == nil)
    #expect(f.vm.isDeleted == false)
    #expect(f.vm.isLoading == false)
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func load_doesNotRewriteDatesFromStoredTitle() async {
    // Regression: loading must apply the stored dates verbatim, not re-derive
    // them from NL expressions that happen to sit in the stored title.
    let item = WorkItem(
        kind: .task,
        title: "Ship it in two days",
        startAt: date(2026, 11, 10, hour: 9),
        endAt: date(2026, 11, 10, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    #expect(f.vm.edit.startAt == date(2026, 11, 10, hour: 9))
    #expect(f.vm.edit.endAt == date(2026, 11, 10, hour: 17))
}

@Test @MainActor
func load_withDonePrerequisite_keepsStoredStatus() async {
    let item = WorkItem(kind: .task, title: "Ship release", status: .todo)
    let donePrereq = WorkItem(
        kind: .task, title: "Sign NDA",
        status: .done, completedAt: date(2026, 11, 2, hour: 12)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.repository.seed(donePrereq)
    await f.linkRepository.seed(ItemLink(fromId: donePrereq.id, toId: item.id))
    await f.vm.load()

    #expect(f.vm.status == .todo)
    #expect(f.vm.displayStatus == .todo, "a done prerequisite must not block")
    #expect(f.vm.blockers.map(\.id) == [donePrereq.id])
}

// MARK: - Committing inline edits (FR-22)

@Test @MainActor
func commit_persistsEditedFields() async {
    let item = WorkItem(
        kind: .task, title: "Old title",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    f.vm.edit.title = "New title"
    f.vm.edit.descriptionMd = "New body"
    f.vm.edit.startAt = date(2026, 11, 6, hour: 9)
    f.vm.edit.endAt = date(2026, 11, 6, hour: 17)
    await f.vm.commit()

    let saved = await f.repository.item(item.id)
    #expect(saved?.title == "New title")
    #expect(saved?.descriptionMd == "New body")
    #expect(saved?.startAt == date(2026, 11, 6, hour: 9))
    #expect(saved?.endAt == date(2026, 11, 6, hour: 17))
    #expect(saved?.version == 2)
    #expect(saved?.updatedAt == testNow)
    #expect(f.vm.lastError == nil)
}

@Test @MainActor
func commit_withNoChanges_isNoOp() async {
    let item = WorkItem(
        kind: .task, title: "Stable",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.commit()

    let saved = await f.repository.item(item.id)
    #expect(saved?.version == 1, "an unchanged commit must not bump the revision")
    #expect(saved?.updatedAt == item.updatedAt)
}

@Test @MainActor
func commit_withEmptyTitle_setsError() async {
    let item = WorkItem(kind: .task, title: "Keep me")
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    f.vm.edit.title = "   "
    await f.vm.commit()

    #expect(f.vm.lastError == "Title can't be empty.")
    let saved = await f.repository.item(item.id)
    #expect(saved?.title == "Keep me")
    #expect(saved?.version == 1)
}

// MARK: - Natural-language dates (FR-05)

@Test @MainActor
func typingNaturalLanguageDateInTitle_updatesDates() async {
    let item = WorkItem(
        kind: .task, title: "Ship it",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    f.vm.edit.title = "Ship it in two days"

    // "in two days" from Tue 10:00 → Thu 2026-11-05, business start / EOB.
    #expect(f.vm.edit.startAt == date(2026, 11, 5, hour: 9))
    #expect(f.vm.edit.endAt == date(2026, 11, 5, hour: 17))
}

@Test @MainActor
func typingNaturalLanguageDateInDescription_updatesDates() async {
    let item = WorkItem(
        kind: .task, title: "Ship it",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    f.vm.edit.descriptionMd = "Due midnight"

    // Midnight of the current day is in the past at 10:00 → rolls to
    // Wed 2026-11-04 00:00; the due time is that day's EOB.
    #expect(f.vm.edit.startAt == date(2026, 11, 4, hour: 0))
    #expect(f.vm.edit.endAt == date(2026, 11, 4, hour: 17))
}

@Test @MainActor
func manualDates_surviveTypingDatelessTitles() async {
    let item = WorkItem(
        kind: .task, title: "Review",
        startAt: date(2026, 11, 10, hour: 9),
        endAt: date(2026, 11, 10, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    f.vm.edit.title = "Review the contract carefully"

    #expect(f.vm.edit.startAt == date(2026, 11, 10, hour: 9))
    #expect(f.vm.edit.endAt == date(2026, 11, 10, hour: 17))
}

// MARK: - Complete (FR-14)

@Test @MainActor
func complete_marksDoneAndStampsCompletedAt() async {
    let item = WorkItem(kind: .task, title: "Small task", status: .todo)
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.complete()

    #expect(f.vm.item?.status == .done)
    #expect(f.vm.item?.completedAt == testNow)
    #expect(f.vm.progress == RollUpProgress.Result(done: 1, total: 1, fraction: 1))
    let saved = await f.repository.item(item.id)
    #expect(saved?.status == .done)
    #expect(saved?.completedAt == testNow)
}

@Test @MainActor
func complete_blockedByOpenPrerequisite_setsError() async {
    let item = WorkItem(kind: .task, title: "Ship release", status: .todo)
    let openPrereq = WorkItem(kind: .task, title: "Sign NDA", status: .inProgress)
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.repository.seed(openPrereq)
    await f.linkRepository.seed(ItemLink(fromId: openPrereq.id, toId: item.id))
    await f.vm.load()

    await f.vm.complete()

    #expect(f.vm.lastError == "Blocked by: Sign NDA")
    #expect(f.vm.item?.status == .todo)
    let saved = await f.repository.item(item.id)
    #expect(saved?.status == .todo)
}

@Test @MainActor
func complete_blockedWithForce_succeeds() async {
    let item = WorkItem(kind: .task, title: "Ship release", status: .todo)
    let openPrereq = WorkItem(kind: .task, title: "Sign NDA", status: .inProgress)
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.repository.seed(openPrereq)
    await f.linkRepository.seed(ItemLink(fromId: openPrereq.id, toId: item.id))
    await f.vm.load()

    await f.vm.complete(force: true)

    #expect(f.vm.item?.status == .done)
    #expect(f.vm.lastError == nil)
}

// MARK: - Status / priority (FR-20)

@Test @MainActor
func setStatus_reopensDoneItem() async {
    let item = WorkItem(
        kind: .task, title: "Shipped",
        status: .done, completedAt: date(2026, 11, 2, hour: 15)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.setStatus(.todo)

    #expect(f.vm.status == .todo)
    #expect(f.vm.item?.completedAt == nil)
    let saved = await f.repository.item(item.id)
    #expect(saved?.status == .todo)
    #expect(saved?.completedAt == nil)
}

@Test @MainActor
func setPriority_persists() async {
    let item = WorkItem(kind: .task, title: "Bump me", priority: .normal)
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.setPriority(.urgent)

    #expect(f.vm.priority == .urgent)
    let saved = await f.repository.item(item.id)
    #expect(saved?.priority == .urgent)
    #expect(saved?.version == 2)
}

// MARK: - Move to tomorrow (FR-42/43)

@Test @MainActor
func moveToTomorrow_shiftsOnlyEndAt() async {
    let item = WorkItem(
        kind: .task, title: "Carry over",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.moveToTomorrow()

    // Tuesday → the next working day is Wednesday, at its EOB.
    #expect(f.vm.item?.endAt == date(2026, 11, 4, hour: 17))
    #expect(f.vm.item?.startAt == date(2026, 11, 3, hour: 9))
    #expect(f.vm.edit.endAt == date(2026, 11, 4, hour: 17))
    let saved = await f.repository.item(item.id)
    #expect(saved?.endAt == date(2026, 11, 4, hour: 17))
}

// MARK: - Delete (FR-32)

@Test @MainActor
func delete_softDeletesAndCloses() async {
    let item = WorkItem(kind: .task, title: "Trash me")
    let closed = ClosedLog()
    let f = Fixture(itemId: item.id, onClosed: { closed.record() })
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.delete()

    #expect(f.vm.isDeleted == true)
    #expect(f.vm.item == nil)
    #expect(closed.count == 1)
    #expect(await f.repository.item(item.id) == nil, "soft-deleted items must not load")
}

// MARK: - Date shortcuts (FR-22)

@Test @MainActor
func applyDateShortcut_tomorrowEOB_persists() async {
    let item = WorkItem(
        kind: .task, title: "Due soon",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.applyDateShortcut(.tomorrowEOB)

    #expect(f.vm.edit.endAt == date(2026, 11, 4, hour: 17))
    let saved = await f.repository.item(item.id)
    #expect(saved?.endAt == date(2026, 11, 4, hour: 17))
}

@Test @MainActor
func applyDateShortcut_nextMonday_setsBusinessStart() async {
    let item = WorkItem(
        kind: .task, title: "Monday work",
        startAt: date(2026, 11, 3, hour: 9),
        endAt: date(2026, 11, 3, hour: 17)
    )
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.applyDateShortcut(.nextMonday)

    // Tuesday 2026-11-03 → the next Monday is 2026-11-09, at business start.
    #expect(f.vm.edit.endAt == date(2026, 11, 9, hour: 9))
    let saved = await f.repository.item(item.id)
    #expect(saved?.endAt == date(2026, 11, 9, hour: 9))
}

// MARK: - Attachments

@Test @MainActor
func removeAttachment_removesIt() async {
    let item = WorkItem(kind: .task, title: "With files")
    let keep = Attachment(itemId: item.id, kind: .file, displayName: "keep.pdf")
    let drop = Attachment(itemId: item.id, kind: .image, displayName: "drop.png")
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.attachmentRepository.seed(keep)
    await f.attachmentRepository.seed(drop)
    await f.vm.load()

    await f.vm.removeAttachment(drop.id)

    #expect(f.vm.attachments.map(\.id) == [keep.id])
    #expect((await f.attachmentRepository.all).map(\.id) == [keep.id])
}

// MARK: - Links (FR-30)

@Test @MainActor
func addLink_createsBlockerAndRefreshesSections() async {
    let item = WorkItem(title: "Ship it", startAt: date(2026, 11, 3, hour: 9), endAt: date(2026, 11, 3, hour: 17))
    let prerequisite = WorkItem(title: "Get approval", startAt: date(2026, 11, 3, hour: 9), endAt: date(2026, 11, 3, hour: 12))
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.repository.seed(prerequisite)
    await f.vm.load()

    await f.vm.addLink(to: prerequisite.id, kind: .blocks)

    #expect(f.vm.lastError == nil)
    #expect(f.vm.blockers.map(\.title) == ["Get approval"])
    let links = await f.linkRepository.allLinks()
    #expect(links.contains { $0.fromId == prerequisite.id && $0.toId == item.id && $0.kind == .blocks })
}

@Test @MainActor
func addLink_rejectsASelfLinkImplicitly() async {
    let item = WorkItem(title: "Ship it", startAt: date(2026, 11, 3, hour: 9), endAt: date(2026, 11, 3, hour: 17))
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.vm.load()

    await f.vm.addLink(to: item.id, kind: .blocks)

    #expect(f.vm.blockers.isEmpty)
    #expect(f.vm.related.isEmpty)
}

// MARK: - Activity log (FR-20)

@Test @MainActor
func load_readsNewestActivityFirst() async {
    let item = WorkItem(title: "Ship it", startAt: date(2026, 11, 3, hour: 9), endAt: date(2026, 11, 3, hour: 17))
    let f = Fixture(itemId: item.id)
    await f.repository.seed(item)
    await f.activityRepository.seed(
        ActivityEvent(
            itemId: item.id,
            kind: .created,
            summary: "Created “Ship it”",
            actor: "tester",
            occurredAt: date(2026, 11, 3, hour: 9)
        )
    )
    await f.activityRepository.seed(
        ActivityEvent(
            itemId: item.id,
            kind: .dropped,
            summary: "Dropped “shot.png”",
            actor: "tester",
            sourceApp: "com.apple.finder",
            location: "/tmp/shot.png",
            occurredAt: date(2026, 11, 3, hour: 10)
        )
    )

    await f.vm.load()

    #expect(f.vm.activity.map(\.summary) == [
        "Dropped “shot.png”",
        "Created “Ship it”",
    ])
    #expect(f.vm.activity.first?.sourceApp == "com.apple.finder")
    #expect(f.vm.activity.first?.location == "/tmp/shot.png")
}
