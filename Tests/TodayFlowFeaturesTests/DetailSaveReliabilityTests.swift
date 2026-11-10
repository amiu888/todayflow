import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

/// Wraps the in-memory repository so a test can make the next saves fail,
/// slow them down, or silently drop them.
private actor ControlledRepository: WorkItemRepository {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The database is locked." }
    }

    let inner = InMemoryWorkItemRepository()
    var failuresRemaining = 0
    var dropWrites = false
    var saveDelay: Duration = .zero
    private(set) var saveCount = 0

    func setFailures(_ count: Int) { failuresRemaining = count }
    func setDropWrites(_ drop: Bool) { dropWrites = drop }
    func setDelay(_ delay: Duration) { saveDelay = delay }
    func seed(_ item: WorkItem) async { await inner.seed(item) }

    func item(_ id: UUIDv7) async -> WorkItem? { await inner.item(id) }
    func todayItems(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        await inner.todayItems(on: day, calendar: calendar)
    }
    func completedToday(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        await inner.completedToday(on: day, calendar: calendar)
    }
    func children(of parentId: UUIDv7?) async -> [WorkItem] { await inner.children(of: parentId) }
    func allItems() async -> [WorkItem] { await inner.allItems() }
    func save(_ item: WorkItem) async throws {
        saveCount += 1
        if saveDelay != .zero { try? await Task.sleep(for: saveDelay) }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw Failure()
        }
        if dropWrites { return }
        try await inner.save(item)
    }
    func softDelete(_ id: UUIDv7, at: Date) async throws { try await inner.softDelete(id, at: at) }
    func move(_ id: UUIDv7, toParent: UUIDv7?, displayOrder: String, at: Date) async throws {
        try await inner.move(id, toParent: toParent, displayOrder: displayOrder, at: at)
    }
    func observeToday(on day: Date, calendar: WorkCalendar) async -> AsyncStream<[WorkItem]> {
        await inner.observeToday(on: day, calendar: calendar)
    }
    func search(_ query: String) async -> [WorkItem] { await inner.search(query) }
}

@MainActor
private func makeModel(_ repository: ControlledRepository, item: WorkItem) async -> DetailViewModel {
    await repository.seed(item)
    let model = DetailViewModel(
        itemId: item.id,
        repository: repository,
        linkRepository: InMemoryLinkRepository(),
        attachmentRepository: InMemoryAttachmentRepository()
    )
    await model.load()
    return model
}

@Test @MainActor
func saveRetriesATransientFailureAndConfirmsTheWrite() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft")
    let model = await makeModel(repository, item: item)
    await repository.setFailures(2)

    model.edit.title = "Final title"
    let saved = await model.commit()

    #expect(saved)
    #expect(model.lastError == nil)
    #expect(model.hasUnsavedChanges == false)
    #expect(await repository.item(item.id)?.title == "Final title")
}

@Test @MainActor
func aSaveThatKeepsFailingKeepsTheEditsAndTellsTheUser() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft")
    let model = await makeModel(repository, item: item)
    await repository.setFailures(10)

    var closed = false
    model.onSavedAndClosed = { closed = true }
    model.edit.descriptionMd = "Important notes"
    await model.saveAndClose()

    #expect(closed == false)
    #expect(model.lastError?.contains("Couldn't save your changes.") == true)
    #expect(model.lastError?.contains("The database is locked.") == true)
    #expect(model.edit.descriptionMd == "Important notes")
    #expect(model.hasUnsavedChanges)

    // The error survives a background reload, and Try Again then succeeds.
    await model.load()
    #expect(model.lastError != nil)
    #expect(model.edit.descriptionMd == "Important notes")
    await repository.setFailures(0)
    await model.saveAndClose()
    #expect(closed)
    #expect(model.lastError == nil)
    #expect(await repository.item(item.id)?.descriptionMd == "Important notes")
}

@Test @MainActor
func aWriteThatDoesNotLandIsReportedInsteadOfShownAsSaved() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft")
    let model = await makeModel(repository, item: item)
    await repository.setDropWrites(true)

    model.edit.title = "Lost?"
    let saved = await model.commit()

    #expect(saved == false)
    #expect(model.lastSavedAt == nil)
    #expect(model.lastError?.contains("doesn't match") == true)
    #expect(model.hasUnsavedChanges)
}

@Test @MainActor
func saveClickedDuringAnAutosaveIsNotDropped() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft")
    let model = await makeModel(repository, item: item)
    await repository.setDelay(.milliseconds(80))

    model.edit.title = "First"
    let autosave = Task { await model.commit() }
    try? await Task.sleep(for: .milliseconds(10))
    model.edit.title = "Second"
    let clicked = await model.commit()
    _ = await autosave.value

    #expect(clicked)
    #expect(await repository.item(item.id)?.title == "Second")
}

@Test @MainActor
func reloadingKeepsTextTheUserHasNotSavedYet() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft", descriptionMd: "old")
    let model = await makeModel(repository, item: item)

    model.edit.descriptionMd = "typing in progress"
    await model.load() // e.g. an attachment was dropped on the window

    #expect(model.edit.descriptionMd == "typing in progress")
    #expect(model.edit.title == "Draft")
}

@Test @MainActor
func saveAndCloseClosesWhenNothingChangedAndRejectsAnEmptyTitle() async {
    let repository = ControlledRepository()
    let item = WorkItem(title: "Draft")
    let model = await makeModel(repository, item: item)
    var closes = 0
    model.onSavedAndClosed = { closes += 1 }

    await model.saveAndClose()
    #expect(closes == 1)

    model.edit.title = "   "
    await model.saveAndClose()
    #expect(closes == 1)
    #expect(model.lastError == "Title can't be empty.")
}
