import Foundation
import TodayFlowCore
import TodayFlowRecognition

/// The brain of the quick-add capture sheet (driver.md §7 step 4).
///
/// Owns the editable `CaptureDraft` and the raw `DroppedObject`s behind its
/// `RecognizedObject`s. On save it creates the `WorkItem` via `CreateTask`,
/// materializes each object via `Materializer`, and persists one
/// `Attachment` per object. Natural-language dates in the title or
/// description re-resolve the draft's dates on every edit.
@MainActor
@Observable
public final class CaptureViewModel {
    // MARK: Observed state

    /// The editable draft the sheet renders. Mutating any field (via the
    /// sheet's bindings) triggers the NL date re-parse.
    public var draft: CaptureDraft {
        didSet {
            guard oldValue.title != draft.title
                || oldValue.descriptionMd != draft.descriptionMd
            else { return }
            reparseDates()
        }
    }

    /// Projects the sheet's parent (project) picker offers.
    public private(set) var parents: [CaptureParentOption] = []

    /// True while `save()` is running.
    public private(set) var isSaving = false

    /// The user-facing error from the last failed action.
    public private(set) var lastError: String?

    /// The item `save()` created, if it succeeded.
    public private(set) var savedItem: WorkItem?

    // MARK: Dependencies

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let attachmentRepository: any AttachmentRepository
    @ObservationIgnored private let materializer: Materializer
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let onSaved: (@MainActor (UUIDv7) -> Void)?
    @ObservationIgnored private let onCancel: (@MainActor () -> Void)?

    /// Raw drops, index-aligned with `draft.objects`.
    @ObservationIgnored private var droppedObjects: [DroppedObject] = []

    public init(
        repository: any WorkItemRepository,
        attachmentRepository: any AttachmentRepository,
        materializer: Materializer,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        onSaved: (@MainActor (UUIDv7) -> Void)? = nil,
        onCancel: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.attachmentRepository = attachmentRepository
        self.materializer = materializer
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
        self.onSaved = onSaved
        self.onCancel = onCancel
        let now = clock()
        self.draft = CaptureDraft(
            title: "",
            startAt: now,
            endAt: calendar.defaultEndAt(createdAt: now)
        )
    }

    // MARK: Actions

    /// Offers the sheet's parent (project) picker.
    public func setParents(_ parents: [CaptureParentOption]) {
        self.parents = parents
    }

    /// Loads the parent picker's options from the repository: every project,
    /// in display order. Projects may stand alone or live under an epic
    /// (driver.md §2), so no further filtering is needed.
    public func loadParents() async {
        let all = await repository.allItems()
        parents = all
            .filter { $0.kind == .project }
            .map { CaptureParentOption(id: $0.id, title: $0.title) }
    }

    /// Prepares the sheet for a new capture: builds the draft from the
    /// recognized objects and records the raw drops for materialization.
    /// The draft assignment triggers the NL date re-parse (a suggested title
    /// like "Invoice due in two days" sets the dates).
    public func prepare(
        dropped: [DroppedObject],
        recognized: [RecognizedObject],
        parentId: UUIDv7? = nil
    ) {
        let now = clock()
        self.draft = CaptureDraftBuilder(calendar: calendar)
            .build(objects: recognized, at: now, parentId: parentId)
        self.droppedObjects = dropped
        self.savedItem = nil
        self.lastError = nil
        self.isSaving = false
    }

    /// Removes a draft object (the sheet's chip × button), keeping the raw
    /// drops index-aligned.
    public func removeObject(at index: Int) {
        guard droppedObjects.indices.contains(index),
              draft.objects.indices.contains(index)
        else { return }
        draft.objects.remove(at: index)
        droppedObjects.remove(at: index)
    }

    /// Applies the slow enrichment result (driver.md §7 step 5) without
    /// disturbing anything the user has edited since the sheet opened.
    ///
    /// Only objects keep their new metadata; the title follows the enriched
    /// suggestion while it is still the inferred title (or empty). If the user
    /// has typed their own title, it is left alone.
    public func applyEnrichment(_ enriched: CaptureDraft) {
        guard enriched.objects.count == draft.objects.count else { return }
        let previous = draft.objects

        for index in draft.objects.indices
        where previous[index].type == enriched.objects[index].type {
            draft.objects[index] = enriched.objects[index]
        }

        for index in previous.indices {
            let inferred = previous[index].suggestedTitle ?? previous[index].displayName
            let titleIsInferred = draft.title.isEmpty || draft.title == inferred
            guard titleIsInferred,
                  let suggestion = enriched.objects[index].suggestedTitle,
                  !suggestion.isEmpty
            else { continue }
            draft.title = suggestion
            break
        }
    }

    /// Creates the work item and its attachments from the current draft.
    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        lastError = nil
        defer { isSaving = false }

        let now = clock()
        do {
            let input = CreateTask.Input(
                kind: .task,
                title: draft.title,
                descriptionMd: draft.descriptionMd,
                parentId: draft.parentId,
                startAt: draft.startAt,
                endAt: draft.endAt,
                priority: draft.priority
            )
            let item = try await CreateTask(
                repository: repository,
                calendar: calendar,
                deviceId: deviceId
            ).execute(input)

            for (dropped, object) in zip(droppedObjects, draft.objects) {
                // The recognition pipeline already materialized this object
                // (a transient copy or a bookmark). Materializing again would
                // duplicate transient files; only do it when the caller handed
                // us bare recognized objects.
                let materialized = object.localCopyPath == nil && object.bookmark == nil
                    ? materializer.materialize(object, source: dropped)
                    : object
                var attachment = materialized.attachment(for: item.id, at: now)
                attachment.deviceId = deviceId
                try await attachmentRepository.save(attachment)
            }

            savedItem = item
            onSaved?(item.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Discards the draft and closes the sheet.
    public func cancel() {
        let now = clock()
        draft = CaptureDraft(
            title: "",
            startAt: now,
            endAt: calendar.defaultEndAt(createdAt: now)
        )
        droppedObjects = []
        savedItem = nil
        lastError = nil
        onCancel?()
    }

    // MARK: Natural-language dates

    /// Re-resolves the draft's dates from natural-language expressions in the
    /// title (preferred) or description. Dates are only overwritten when a
    /// match is found, so manual DatePicker edits survive typing.
    private func reparseDates() {
        let now = clock()
        let parser = ParseNaturalLanguageDates(
            calendar: calendar.calendar,
            workCalendar: calendar
        )
        if let hit = parser.parse(draft.title, at: now).first {
            draft.startAt = hit.start
            draft.endAt = hit.end
        } else if let hit = parser.parse(draft.descriptionMd, at: now).first {
            draft.startAt = hit.start
            draft.endAt = hit.end
        }
    }
}
