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
            guard !isApplyingSuggestion else { return }
            guard oldValue.title != draft.title
                || oldValue.descriptionMd != draft.descriptionMd
            else { return }
            reparseDates()
        }
    }

    /// Optional AI client; set by the host only when AI and the "suggest"
    /// feature are enabled (driver.md §8). Capture works without it.
    @ObservationIgnored public var assistant: (any AIAssistant)?
    /// Optional email summarizer. When nil (AI off, no provider, or the
    /// feature disabled) the task is saved without a summary.
    @ObservationIgnored public var emailSummarizer: (any EmailSummarizer)?
    /// Resolves the summarizer at save time, so a capture saved immediately
    /// after the panel opens still gets a summary once Settings has loaded.
    @ObservationIgnored public var emailSummarizerProvider:
        (@MainActor () async -> (any EmailSummarizer)?)?

    /// Projects the sheet's parent (project) picker offers.
    public private(set) var parents: [CaptureParentOption] = []

    /// True while `save()` is running.
    public private(set) var isSaving = false

    /// The user-facing error from the last failed action.
    public private(set) var lastError: String?

    /// The item `save()` created, if it succeeded (the last one when an
    /// ⌥-drop was split into one task per object).
    public private(set) var savedItem: WorkItem?
    /// True when the drop should create one task per object (FR-01, ⌥ held).
    public private(set) var splitsIntoTasks = false

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
    /// Suppresses the natural-language re-parse while AI fills in a suggestion.
    @ObservationIgnored private var isApplyingSuggestion = false
    /// Attachments already persisted by a partially failed save, so retrying
    /// "Add" does not create a duplicate task or duplicate rows.
    @ObservationIgnored private var savedAttachmentCount = 0

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
            // A capture belongs to today's plan: due at today's end of
            // business, even when created after hours.
            endAt: calendar.endOfBusiness(for: now)
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
        parentId: UUIDv7? = nil,
        splitIntoTasks: Bool = false
    ) {
        let now = clock()
        self.draft = CaptureDraftBuilder(calendar: calendar)
            .build(objects: recognized, at: now, parentId: parentId)

        // An empty keyboard capture must start empty, not with the literal
        // placeholder “New task” (which users would then append to).
        if recognized.isEmpty {
            draft.title = ""
            draft.descriptionMd = ""
        }

        // Explicit dates in the title/description still win, but a plain
        // capture is due at today's end of business (not tomorrow's), so it
        // shows up on the Today plan immediately.
        let parser = ParseNaturalLanguageDates(
            calendar: calendar.calendar,
            workCalendar: calendar
        )
        let hasExplicitDate = !parser.parse(draft.title, at: now).isEmpty
            || !parser.parse(draft.descriptionMd, at: now).isEmpty
        if !hasExplicitDate {
            draft.startAt = now
            draft.endAt = calendar.endOfBusiness(for: now)
        }

        self.droppedObjects = dropped
        self.splitsIntoTasks = splitIntoTasks
            && recognized.count > 1
            && dropped.count == recognized.count
        self.savedItem = nil
        self.lastError = nil
        self.isSaving = false
        self.savedAttachmentCount = 0
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

    /// Asks the optional AI client for a smarter title/summary (driver.md §8
    /// "Smart title and summary"). Failures are silent: AI must never block
    /// capture, and the user can always save the draft as-is.
    public func requestAISuggestion() async {
        guard let assistant, !draft.objects.isEmpty else { return }
        guard let suggestion = try? await assistant.suggestTask(from: draft.objects) else {
            return
        }
        applySuggestion(suggestion)
    }

    /// Applies a suggestion without overwriting fields the user already
    /// edited. The summary goes into the description only when it is empty.
    public func applySuggestion(_ suggestion: TaskSuggestion) {
        let inferred = draft.objects
            .compactMap { $0.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            ?? draft.objects.first?.displayName
        let titleIsInferred = draft.title.isEmpty || draft.title == inferred

        isApplyingSuggestion = true
        defer { isApplyingSuggestion = false }

        if titleIsInferred, !suggestion.title.isEmpty {
            draft.title = suggestion.title
        }
        if draft.descriptionMd.isEmpty {
            var parts: [String] = []
            if !suggestion.summary.isEmpty { parts.append(suggestion.summary) }
            if !suggestion.actions.isEmpty {
                parts.append(suggestion.actions.map { "- [ ] \($0)" }.joined(separator: "\n"))
            }
            draft.descriptionMd = parts.joined(separator: "\n\n")
        }
        if draft.priority == .default {
            draft.priority = suggestion.priority
        }
    }

    /// Creates the work item and its attachments from the current draft.
    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        lastError = nil
        Diagnostics.log(
            "capture",
            "save start title=“\(draft.title)” objects=\(draft.objects.count) "
                + "dropped=\(droppedObjects.count) split=\(splitsIntoTasks)"
        )
        defer { isSaving = false }

        let now = clock()
        do {
            let create = CreateTask(
                repository: repository,
                calendar: calendar,
                deviceId: deviceId
            )

            if splitsIntoTasks {
                // FR-01 ⌥-drop: one task per object, each with its own
                // attachment. The sheet's shared dates/priority still apply.
                for (dropped, object) in zip(droppedObjects, draft.objects) {
                    let suggested = object.suggestedTitle?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let title = suggested.isEmpty ? object.displayName : suggested
                    let item = try await create.execute(
                        CreateTask.Input(
                            kind: .task,
                            title: title,
                            descriptionMd: object.type == .text ? object.previewText ?? "" : "",
                            parentId: draft.parentId,
                            startAt: draft.startAt,
                            endAt: draft.endAt,
                            priority: draft.priority,
                            placement: .top
                        )
                    )
                    try await saveAttachment(object, source: dropped, for: item.id, at: now)
                    scheduleEmailSummary(for: item, object: object, source: dropped, at: now)
                    savedItem = item
                }
                if let savedItem { onSaved?(savedItem.id) }
                return
            }

            let item: WorkItem
            if let existing = savedItem {
                // Retry after an attachment failed: the task already exists.
                item = existing
            } else {
                item = try await create.execute(
                    CreateTask.Input(
                        kind: .task,
                        title: draft.title,
                        descriptionMd: draft.descriptionMd,
                        parentId: draft.parentId,
                        startAt: draft.startAt,
                        endAt: draft.endAt,
                        priority: draft.priority,
                        placement: .top
                    )
                )
                savedItem = item
            }

            let pending = Array(zip(droppedObjects, draft.objects))
                .dropFirst(savedAttachmentCount)
            for (dropped, object) in pending {
                try await saveAttachment(object, source: dropped, for: item.id, at: now)
                savedAttachmentCount += 1
            }

            if let email = zip(droppedObjects, draft.objects)
                .first(where: { $0.1.type == .email })
            {
                scheduleEmailSummary(
                    for: item,
                    object: email.1,
                    source: email.0,
                    at: now
                )
            }

            Diagnostics.log("capture", "save ok item=\(item.id) title=“\(item.title)”")
            onSaved?(item.id)
        } catch {
            Diagnostics.log("capture", "save FAILED: \(error)")
            lastError = error.localizedDescription
        }
    }

    /// Builds a digest from the recognized email and the raw drop. `.eml` and
    /// `.msg` files carry the body in `previewText`; Mail's `message://` drops
    /// fall back to the pasteboard text (subject/body) when the source app
    /// provides it.
    private func emailDigest(
        _ object: RecognizedObject,
        source: DroppedObject
    ) -> EmailDigest? {
        guard object.type == .email else { return nil }
        let candidates = [
            object.previewText,
            source.text,
        ]
        let body = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max { $0.count < $1.count }
            ?? ""
        let subject = (object.suggestedTitle ?? object.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty || !body.isEmpty else { return nil }
        let received = object.metadata[MetadataKeys.receivedAt].flatMap(Iso8601.decode)
        return EmailDigest(
            subject: subject,
            sender: object.metadata[MetadataKeys.sender] ?? object.metadata[MetadataKeys.from],
            recipients: object.metadata[MetadataKeys.to],
            body: body,
            sourceApp: object.sourceApp ?? source.sourceApp,
            receivedAt: received
        )
    }

    /// Summarizes in the background so saving never waits on the network (or
    /// on Apple Intelligence). A failure leaves the summary empty.
    private func scheduleEmailSummary(
        for item: WorkItem,
        object: RecognizedObject,
        source: DroppedObject,
        at now: Date
    ) {
        guard let digest = emailDigest(object, source: source) else { return }

        let direct = emailSummarizer
        let provider = emailSummarizerProvider
        let repository = self.repository
        let deviceId = self.deviceId
        Task { @MainActor in
            let summarizer: (any EmailSummarizer)?
            if let direct {
                summarizer = direct
            } else {
                summarizer = await provider?()
            }
            guard let summarizer else {
                Diagnostics.log("ai", "email summary unavailable item=\(item.id)")
                return
            }
            guard let summary = try? await summarizer.summarize(digest) else {
                Diagnostics.log("ai", "email summary skipped item=\(item.id)")
                return
            }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  var latest = await repository.item(item.id)
            else { return }
            latest.summary = String(trimmed.prefix(1_200))
            latest.updatedAt = now
            latest.version += 1
            latest.deviceId = deviceId
            try? await repository.save(latest)
            Diagnostics.log("ai", "email summary item=\(item.id) chars=\(trimmed.count)")
            NotificationCenter.default.post(
                name: TodayFlowEvents.itemsChanged,
                object: nil
            )
        }
    }

    /// Persists one attachment, using the pipeline's copy/bookmark when present
    /// so transient files are never copied twice.
    private func saveAttachment(
        _ object: RecognizedObject,
        source: DroppedObject,
        for itemId: UUIDv7,
        at date: Date
    ) async throws {
        let materialized = object.localCopyPath == nil && object.bookmark == nil
            ? materializer.materialize(object, source: source)
            : object
        var attachment = materialized.attachment(for: itemId, at: date)
        attachment.deviceId = deviceId
        // Provenance for the activity log: a dropped object is distinguishable
        // from an attachment added later in the detail view.
        if source.fileURL != nil || source.url != nil
            || source.text != nil || source.imageData != nil
        {
            attachment.metadata["origin"] = "drop"
            if let sourceApp = source.sourceApp {
                attachment.sourceApp = sourceApp
            }
            if let uti = source.uti {
                attachment.metadata["drop_uti"] = uti.identifier
            }
        }
        try await attachmentRepository.save(attachment)
    }

    /// Discards the draft and closes the sheet.
    public func cancel() {
        let now = clock()
        draft = CaptureDraft(
            title: "",
            startAt: now,
            endAt: calendar.endOfBusiness(for: now)
        )
        droppedObjects = []
        savedItem = nil
        lastError = nil
        savedAttachmentCount = 0
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
