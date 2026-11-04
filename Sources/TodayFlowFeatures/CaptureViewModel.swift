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
                var attachment = materializer
                    .materialize(object, source: dropped)
                    .attachment(for: item.id, at: now)
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
