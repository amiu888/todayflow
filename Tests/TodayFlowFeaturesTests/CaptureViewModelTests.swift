import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowRecognition

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
    hour: Int, minute: Int = 0, second: Int = 0
) -> Date {
    testCalendar.date(
        from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
    )!
}

// MARK: - Fakes

/// `FileAccess` stub. Succeeds by default; `fail = true` makes every mutating
/// call throw, and `bookmarkData` is what `securityScopedBookmark` returns.
private struct FakeFileAccess: FileAccess {
    var fail = false
    var bookmarkData: Data? = Data([0x42])

    func isDirectory(_ url: URL) -> Bool? { nil }
    func size(of url: URL) -> Int64? { nil }
    func modificationDate(of url: URL) -> Date? { nil }

    func copy(from source: URL, to destination: URL) throws {
        if fail { throw CopyError() }
    }

    func write(_ data: Data, to url: URL) throws {
        if fail { throw CopyError() }
    }

    func securityScopedBookmark(for url: URL) -> Data? {
        fail ? nil : bookmarkData
    }

    func url(fromSecurityScopedBookmark data: Data) -> URL? { nil }

    func createDirectory(_ url: URL) throws {
        if fail { throw CopyError() }
    }

    struct CopyError: Error {}
}

/// Records the ids passed to the VM's `onSaved` callback.
@MainActor
private final class SavedLog {
    private(set) var ids: [UUIDv7] = []
    func record(_ id: UUIDv7) { ids.append(id) }
}

/// Records calls to the VM's `onCancel` callback.
@MainActor
private final class CancelLog {
    private(set) var count = 0
    func record() { count += 1 }
}

// MARK: - Fixture

@MainActor
private struct Fixture {
    let repository = InMemoryWorkItemRepository()
    let attachmentRepository = InMemoryAttachmentRepository()
    let fileAccess = FakeFileAccess()
    let calendar = WorkCalendar(calendar: testCalendar)
    let now = testNow
    let vm: CaptureViewModel

    init(
        onSaved: (@MainActor (UUIDv7) -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        let materializer = Materializer(
            fileAccess: fileAccess,
            attachmentsDirectory: URL(fileURLWithPath: "/tmp/todayflow-test-attachments")
        )
        self.vm = CaptureViewModel(
            repository: repository,
            attachmentRepository: attachmentRepository,
            materializer: materializer,
            calendar: calendar,
            clock: { testNow },
            onSaved: onSaved,
            onCancel: onCancel
        )
    }
}

// MARK: - Parent picker

@Test @MainActor
func loadParents_listsProjectsInDisplayOrder() async {
    let f = Fixture()
    let epic = WorkItem(kind: .epic, title: "Epic", displayOrder: "a")
    let first = WorkItem(kind: .project, title: "First", displayOrder: "b")
    let second = WorkItem(kind: .project, title: "Second", displayOrder: "c")
    let task = WorkItem(title: "Task", displayOrder: "d")
    for item in [epic, second, first, task] {
        await f.repository.seed(item)
    }

    await f.vm.loadParents()

    #expect(f.vm.parents.map(\.title) == ["First", "Second"])
    #expect(f.vm.parents.map(\.id) == [first.id, second.id])
}

// MARK: - prepare

@Test @MainActor
func prepare_buildsDraftFromRecognizedObjects() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/contract.pdf"))],
        recognized: [
            RecognizedObject(
                type: .file,
                uti: "com.adobe.pdf",
                displayName: "contract.pdf",
                suggestedTitle: "Review contract"
            )
        ]
    )

    #expect(f.vm.draft.title == "Review contract")
    #expect(f.vm.draft.objects.count == 1)
    // "Review contract" has no date expression, so the builder's defaults stand.
    #expect(f.vm.draft.startAt == f.now) // Tue 10:00
    #expect(f.vm.draft.endAt == date(2026, 11, 3, hour: 17)) // Tue 17:00 EOB
    #expect(f.vm.lastError == nil)
    #expect(f.vm.savedItem == nil)
    #expect(!f.vm.isSaving)
}

@Test @MainActor
func prepare_withSuggestedTitleContainingDate_setsDates() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [],
        recognized: [
            RecognizedObject(type: .text, displayName: "Note", suggestedTitle: "Ship it in two days")
        ]
    )

    #expect(f.vm.draft.title == "Ship it in two days")
    // Tuesday + 2 days = Thursday; a date-only match resolves to the business
    // start, with the due time at that day's EOB.
    #expect(f.vm.draft.startAt == date(2026, 11, 5, hour: 9))
    #expect(f.vm.draft.endAt == date(2026, 11, 5, hour: 17))
}

// MARK: - save

@Test @MainActor
func save_createsItemAndAttachment() async {
    let saved = SavedLog()
    let f = Fixture(onSaved: { saved.record($0) })
    f.vm.prepare(
        dropped: [
            DroppedObject(
                fileURL: URL(fileURLWithPath: "/tmp/contract.pdf"),
                isFilePromise: true
            )
        ],
        recognized: [
            RecognizedObject(
                type: .file,
                uti: "com.adobe.pdf",
                displayName: "contract.pdf",
                suggestedTitle: "Review contract"
            )
        ]
    )

    await f.vm.save()

    #expect(f.vm.lastError == nil)
    #expect(f.vm.savedItem != nil)
    guard let item = f.vm.savedItem else { return }
    #expect(item.title == "Review contract")
    #expect(item.startAt == f.now)
    #expect(item.endAt == date(2026, 11, 3, hour: 17))
    #expect(saved.ids == [item.id])
    #expect(await f.repository.item(item.id) != nil)

    let attachments = await f.attachmentRepository.attachments(for: item.id)
    #expect(attachments.count == 1)
    if let attachment = attachments.first {
        #expect(attachment.itemId == item.id)
        #expect(attachment.kind == .file)
        #expect(attachment.displayName == "contract.pdf")
        #expect(attachment.uti == "com.adobe.pdf")
        // The file promise is copied into the container; the materializer
        // returns early for promises, so no security-scoped bookmark is kept.
        #expect(attachment.localCopyPath != nil)
        #expect(attachment.reference == attachment.localCopyPath)
        #expect(attachment.bookmark == nil)
        #expect(attachment.deviceId == "local")
        #expect(attachment.createdAt == f.now)
    }
}

@Test @MainActor
func save_withNoObjects_createsItemOnly() async {
    let f = Fixture()
    f.vm.prepare(dropped: [], recognized: [])

    await f.vm.save()

    #expect(f.vm.lastError == nil)
    #expect(f.vm.savedItem?.title == "New task")
    #expect(await f.attachmentRepository.all.isEmpty)
}

@Test @MainActor
func save_withEmptyTitle_failsCleanly() async {
    let saved = SavedLog()
    let f = Fixture(onSaved: { saved.record($0) })
    f.vm.prepare(
        dropped: [DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/contract.pdf"))],
        recognized: [
            RecognizedObject(type: .file, displayName: "contract.pdf", suggestedTitle: "Review contract")
        ]
    )
    f.vm.draft.title = "   "

    await f.vm.save()

    #expect(f.vm.savedItem == nil)
    #expect(f.vm.lastError != nil)
    #expect(await f.repository.allItemsIncludingDeleted.isEmpty)
    #expect(saved.ids.isEmpty)
}

@Test @MainActor
func save_persistsParentId() async throws {
    let f = Fixture()
    let project = try await CreateTask(
        repository: f.repository,
        calendar: f.calendar
    ).execute(.init(kind: .project, title: "Website"))

    f.vm.prepare(dropped: [], recognized: [])
    f.vm.draft.title = "Landing page"
    f.vm.draft.parentId = project.id

    await f.vm.save()

    #expect(f.vm.savedItem?.parentId == project.id)
    #expect(await f.repository.item(project.id) != nil)
}

@Test @MainActor
func save_withTwoObjects_createsTwoAttachments() async {
    let f = Fixture()
    f.vm.prepare(
        dropped: [
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/a.pdf")),
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/b.pdf"))
        ],
        recognized: [
            RecognizedObject(type: .file, displayName: "a.pdf", suggestedTitle: "Read a"),
            RecognizedObject(type: .file, displayName: "b.pdf")
        ]
    )

    await f.vm.save()

    guard let item = f.vm.savedItem else {
        Issue.record("save failed: \(String(describing: f.vm.lastError))")
        return
    }
    let attachments = await f.attachmentRepository.attachments(for: item.id)
    #expect(attachments.count == 2)
    // Dictionary storage does not guarantee order — compare as a set.
    #expect(Set(attachments.map(\.displayName)) == ["a.pdf", "b.pdf"])
    #expect(attachments.allSatisfy { $0.itemId == item.id })
    #expect(attachments.allSatisfy { $0.bookmark == Data([0x42]) })
    #expect(Set(attachments.map(\.id)).count == 2)
}

// MARK: - removeObject

@Test @MainActor
func removeObject_keepsDropsAligned() async {
    let f = Fixture()
    f.vm.prepare(
        dropped: [
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/contract.pdf"), isFilePromise: true),
            DroppedObject(imageData: Data([1, 2, 3]))
        ],
        recognized: [
            RecognizedObject(type: .file, displayName: "contract.pdf", suggestedTitle: "Review contract"),
            RecognizedObject(type: .image, displayName: "screenshot.png")
        ]
    )

    f.vm.removeObject(at: 0)

    #expect(f.vm.draft.objects.count == 1)
    #expect(f.vm.draft.objects.first?.displayName == "screenshot.png")

    await f.vm.save()

    let attachments = await f.attachmentRepository.all
    #expect(attachments.count == 1)
    #expect(attachments.first?.kind == .image)
    // The image's data was written into the container.
    #expect(attachments.first?.localCopyPath != nil)
}

// MARK: - Natural-language dates

@Test @MainActor
func typingNaturalLanguageDateInTitle_updatesDates() {
    let f = Fixture()
    f.vm.prepare(dropped: [], recognized: [])

    f.vm.draft.title = "Ship it in two days"

    // Tuesday + 2 days = Thursday; a date-only match resolves to the business
    // start, with the due time at that day's EOB.
    #expect(f.vm.draft.startAt == date(2026, 11, 5, hour: 9))
    #expect(f.vm.draft.endAt == date(2026, 11, 5, hour: 17))
}

@Test @MainActor
func typingNaturalLanguageDateInDescription_updatesDates() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [],
        recognized: [
            RecognizedObject(type: .file, displayName: "contract.pdf", suggestedTitle: "Review contract")
        ]
    )

    f.vm.draft.descriptionMd = "due midnight"

    // Midnight of "now" (Tue 10:00) is already past, so it rolls to the next
    // day; the due time is that day's EOB.
    #expect(f.vm.draft.startAt == date(2026, 11, 4, hour: 0))
    #expect(f.vm.draft.endAt == date(2026, 11, 4, hour: 17))
}

@Test @MainActor
func manualDates_surviveTypingDatelessTitles() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [],
        recognized: [
            RecognizedObject(type: .file, displayName: "contract.pdf", suggestedTitle: "Review contract")
        ]
    )

    f.vm.draft.startAt = date(2026, 11, 3, hour: 13, minute: 30)
    f.vm.draft.endAt = date(2026, 11, 3, hour: 15)
    f.vm.draft.title = "Call Sam"

    #expect(f.vm.draft.startAt == date(2026, 11, 3, hour: 13, minute: 30))
    #expect(f.vm.draft.endAt == date(2026, 11, 3, hour: 15))
}

@Test @MainActor
func manualDates_areHonoredOnSave() async {
    let f = Fixture()
    f.vm.prepare(dropped: [], recognized: [])
    f.vm.draft.title = "Standup"
    f.vm.draft.startAt = date(2026, 11, 3, hour: 8, minute: 15)
    f.vm.draft.endAt = date(2026, 11, 3, hour: 8, minute: 45)

    await f.vm.save()

    #expect(f.vm.savedItem?.startAt == date(2026, 11, 3, hour: 8, minute: 15))
    #expect(f.vm.savedItem?.endAt == date(2026, 11, 3, hour: 8, minute: 45))
}

// MARK: - cancel / parents

@Test @MainActor
func cancel_resetsDraftAndCallsOnCancel() {
    let cancels = CancelLog()
    let f = Fixture(onCancel: { cancels.record() })
    f.vm.prepare(
        dropped: [DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/contract.pdf"))],
        recognized: [
            RecognizedObject(type: .file, displayName: "contract.pdf", suggestedTitle: "Review contract")
        ]
    )
    f.vm.draft.title = "Edited"

    f.vm.cancel()

    #expect(f.vm.draft.title.isEmpty)
    #expect(f.vm.draft.objects.isEmpty)
    #expect(f.vm.savedItem == nil)
    #expect(f.vm.lastError == nil)
    #expect(cancels.count == 1)
}

@Test @MainActor
func setParents_exposesOptionsToSheet() {
    let f = Fixture()
    let options = [
        CaptureParentOption(id: UUIDv7.new(), title: "Website"),
        CaptureParentOption(id: UUIDv7.new(), title: "Marketing")
    ]

    f.vm.setParents(options)

    #expect(f.vm.parents == options)
}

// MARK: - Async enrichment (driver.md §7 step 5)

@Test @MainActor
func applyEnrichment_updatesUrlTitleWhileStillInferred() {
    let f = Fixture()
    let source = URL(string: "https://example.com/article")!
    f.vm.prepare(
        dropped: [DroppedObject(url: source)],
        recognized: [
            RecognizedObject(
                type: .url,
                displayName: "example.com",
                reference: source.absoluteString,
                suggestedTitle: "example.com"
            )
        ]
    )
    #expect(f.vm.draft.title == "example.com")

    var enriched = f.vm.draft
    enriched.objects[0].displayName = "Example Domain"
    enriched.objects[0].suggestedTitle = "Example Domain"
    f.vm.applyEnrichment(enriched)

    #expect(f.vm.draft.objects[0].displayName == "Example Domain")
    #expect(f.vm.draft.title == "Example Domain")
}

@Test @MainActor
func applyEnrichment_preservesUserEditedTitle() {
    let f = Fixture()
    let source = URL(string: "https://example.com/article")!
    f.vm.prepare(
        dropped: [DroppedObject(url: source)],
        recognized: [
            RecognizedObject(
                type: .url,
                displayName: "example.com",
                reference: source.absoluteString,
                suggestedTitle: "example.com"
            )
        ]
    )
    f.vm.draft.title = "Read the article"

    var enriched = f.vm.draft
    enriched.objects[0].displayName = "Example Domain"
    enriched.objects[0].suggestedTitle = "Example Domain"
    f.vm.applyEnrichment(enriched)

    #expect(f.vm.draft.objects[0].displayName == "Example Domain")
    #expect(f.vm.draft.title == "Read the article")
}

@Test @MainActor
func applyEnrichment_ignoresMismatchedDrafts() {
    let f = Fixture()
    f.vm.prepare(dropped: [], recognized: [])
    f.vm.draft.title = "Keep me"

    var enriched = f.vm.draft
    enriched.objects = [RecognizedObject(type: .text, displayName: "Unexpected")]
    f.vm.applyEnrichment(enriched)

    #expect(f.vm.draft.objects.isEmpty)
    #expect(f.vm.draft.title == "Keep me")
}

// MARK: - AI suggestions (driver.md §8)

@Test @MainActor
func applySuggestion_fillsUntouchedFields() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [],
        recognized: [
            RecognizedObject(
                type: .file,
                displayName: "notes.txt",
                suggestedTitle: "notes"
            )
        ]
    )

    f.vm.applySuggestion(
        TaskSuggestion(
            title: "Review notes",
            summary: "Skim the notes before standup.",
            priority: .urgent,
            actions: ["Open the file", "Reply to Sam"]
        )
    )

    #expect(f.vm.draft.title == "Review notes")
    #expect(f.vm.draft.descriptionMd.contains("Skim the notes"))
    #expect(f.vm.draft.descriptionMd.contains("- [ ] Open the file"))
    #expect(f.vm.draft.priority == .urgent)
}

@Test @MainActor
func applySuggestion_preservesUserEdits() {
    let f = Fixture()
    f.vm.prepare(
        dropped: [],
        recognized: [
            RecognizedObject(
                type: .file,
                displayName: "notes.txt",
                suggestedTitle: "notes"
            )
        ]
    )
    f.vm.draft.title = "My title"
    f.vm.draft.descriptionMd = "My notes"
    f.vm.draft.priority = .low

    f.vm.applySuggestion(
        TaskSuggestion(title: "AI title", summary: "AI summary", priority: .urgent)
    )

    #expect(f.vm.draft.title == "My title")
    #expect(f.vm.draft.descriptionMd == "My notes")
    #expect(f.vm.draft.priority == .low)
}

@Test @MainActor
func applySuggestion_doesNotReparseDatesFromSummary() {
    let f = Fixture()
    f.vm.prepare(dropped: [], recognized: [])
    let start = f.vm.draft.startAt
    let end = f.vm.draft.endAt

    f.vm.applySuggestion(
        TaskSuggestion(
            title: "Plan the launch",
            summary: "This is due tomorrow at 3pm."
        )
    )

    #expect(f.vm.draft.startAt == start)
    #expect(f.vm.draft.endAt == end)
}

// MARK: - ⌥-drop splitting (FR-01)

@Test @MainActor
func splitDrop_createsOneTaskPerObjectWithItsOwnAttachment() async {
    let f = Fixture()
    let first = RecognizedObject(
        type: .file,
        displayName: "report.pdf",
        suggestedTitle: "report"
    )
    let second = RecognizedObject(
        type: .file,
        displayName: "notes.txt",
        suggestedTitle: "notes"
    )
    f.vm.prepare(
        dropped: [
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/report.pdf")),
            DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/notes.txt")),
        ],
        recognized: [first, second],
        splitIntoTasks: true
    )
    #expect(f.vm.splitsIntoTasks)

    await f.vm.save()

    #expect(f.vm.lastError == nil)
    let items = await f.repository.allItems()
    #expect(items.count == 2)
    #expect(Set(items.map(\.title)) == Set(["report", "notes"]))

    let attachments = await f.attachmentRepository.all
    #expect(attachments.count == 2)
    #expect(Set(attachments.map(\.itemId)) == Set(items.map(\.id)))
    #expect(Set(attachments.map(\.displayName)) == Set(["report.pdf", "notes.txt"]))
}

@Test @MainActor
func singleObjectDrop_ignoresSplitFlag() async {
    let f = Fixture()
    f.vm.prepare(
        dropped: [DroppedObject(fileURL: URL(fileURLWithPath: "/tmp/report.pdf"))],
        recognized: [
            RecognizedObject(type: .file, displayName: "report.pdf", suggestedTitle: "report")
        ],
        splitIntoTasks: true
    )
    #expect(!f.vm.splitsIntoTasks)

    await f.vm.save()

    #expect(await f.repository.allItems().count == 1)
}
