import Foundation
import Observation
import TodayFlowCore

/// The editable fields of the detail window (driver.md FR-20, FR-22).
///
/// Grouped into one struct so the view can bind with a single `$model.edit`
/// and so the NL date re-parse can guard on which fields actually changed
/// (same pattern as `CaptureViewModel.draft`).
public struct DetailEdit: Hashable, Sendable {
    public var title: String
    public var descriptionMd: String
    public var summary: String
    public var startAt: Date
    public var endAt: Date
    public var estimatedMinutes: Int?

    public init(
        title: String = "",
        descriptionMd: String = "",
        summary: String = "",
        startAt: Date = .now,
        endAt: Date = .now,
        estimatedMinutes: Int? = nil
    ) {
        self.title = title
        self.descriptionMd = descriptionMd
        self.summary = summary
        self.startAt = startAt
        self.endAt = endAt
        self.estimatedMinutes = estimatedMinutes
    }

    public init(item: WorkItem) {
        self.init(
            title: item.title,
            descriptionMd: item.descriptionMd,
            summary: item.summary,
            startAt: item.startAt,
            endAt: item.endAt,
            estimatedMinutes: item.estimatedMinutes
        )
    }
}

/// The Jira-style task detail window model (driver.md FR-20, FR-21, FR-22).
///
/// Owns one loaded item and everything the window shows around it: the
/// editable fields, the derived status, attachments, children, links
/// (blockers / blockings / related), the parent, and the progress roll-up.
///
/// Persistence is commit-on-interaction: text and date edits accumulate in
/// `edit` and `commit()` writes them; discrete actions (status, priority,
/// complete, move, delete) go through the Core use cases immediately. Each
/// action first commits any pending inline edits, so a click never loses
/// what the user just typed.
@MainActor
@Observable
public final class DetailViewModel {
    /// FR-22 compact date shortcuts for the due time.
    public enum DateShortcut: String, CaseIterable, Identifiable, Sendable {
        case todayEOB
        case tomorrowEOB
        case plusOneHour
        case nextMonday

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .todayEOB: return "Today EOB"
            case .tomorrowEOB: return "Tomorrow EOB"
            case .plusOneHour: return "+1 hour"
            case .nextMonday: return "Next Monday"
            }
        }
    }

    // MARK: Observed state

    /// The loaded item — the source of truth for everything the window shows.
    /// `nil` before `load()` succeeds and after `delete()`.
    public private(set) var item: WorkItem?

    /// The editable fields (FR-22 inline editing). Mutating `title` or
    /// `descriptionMd` re-resolves NL dates; manual dates survive when no
    /// expression is found.
    public var edit: DetailEdit = DetailEdit() {
        didSet {
            guard !isApplying else { return }
            guard oldValue.title != edit.title
                || oldValue.descriptionMd != edit.descriptionMd
            else { return }
            reparseDates()
        }
    }

    /// The item's stored status (todo / inProgress / done / cancelled).
    public private(set) var status: Status = .todo

    /// The presentation status: `.blocked` while a prerequisite is open.
    public private(set) var displayStatus: Status = .todo

    public private(set) var attachments: [Attachment] = []
    /// Contacts linked to this task (many-to-many).
    public private(set) var contacts: [Contact] = []
    /// Every contact, for the add-contact picker.
    public private(set) var allContacts: [Contact] = []
    public private(set) var children: [WorkItem] = []
    /// Prerequisites: the `from` end of `.blocks` links pointing at the item.
    public private(set) var blockers: [WorkItem] = []
    /// Dependents: the `to` end of `.blocks` links from the item.
    public private(set) var blockings: [WorkItem] = []
    /// Soft associations (`.relatesTo`), both directions, de-duplicated.
    public private(set) var related: [WorkItem] = []
    /// Items the "Add link" menu can point at (FR-30).
    public private(set) var linkCandidates: [WorkItem] = []
    /// Newest-first audit trail for the Activity section (FR-20).
    public private(set) var activity: [ActivityEvent] = []
    /// The task's optional custom reminder (FR-42).
    public private(set) var reminder: Reminder?
    /// Editable reminder date shown by the detail sheet.
    public var reminderDate: Date = .now
    public private(set) var parent: WorkItem?
    public private(set) var progress: RollUpProgress.Result =
        .init(done: 0, total: 0, fraction: 0)

    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var lastError: String?
    /// Timestamp of the last successful write, for the visible “Saved” state.
    public private(set) var lastSavedAt: Date?

    /// Optional AI client, set by the host only when AI and the "Break down"
    /// feature are enabled (driver.md §8). Suggestions are never persisted
    /// until the user chooses them.
    public var assistant: (any AIAssistant)?
    /// Optional grammar/spelling corrector, enabled by the "Correct spelling
    /// & grammar" feature toggle.
    public var corrector: (any AIAssistant)?
    public private(set) var isCorrectingText = false
    public private(set) var subtaskSuggestions: [SubtaskSuggestion] = []
    public private(set) var isSuggestingSubtasks = false
    /// True once `delete()` succeeded; the host should close the window.
    public private(set) var isDeleted = false

    /// The item's priority, or the default while the item is unloaded.
    public var priority: Priority { item?.priority ?? .default }

    /// True when the host supplied reminder storage (the production app does).
    public var remindersAvailable: Bool { reminderRepository != nil }

    /// The host's "close the window" hook, called after a successful delete.
    @ObservationIgnored public var onClosed: (@MainActor () -> Void)?

    // MARK: Dependencies

    @ObservationIgnored private let itemId: UUIDv7
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let linkRepository: any LinkRepository
    @ObservationIgnored private let attachmentRepository: any AttachmentRepository
    @ObservationIgnored private let contactRepository: (any ContactRepository)?
    @ObservationIgnored private let activityRepository: (any ActivityRepository)?
    @ObservationIgnored private let reminderRepository: (any ReminderRepository)?
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date

    /// While `load()` or an action applies values to `edit`, suppress the NL
    /// re-parse — loading must not rewrite the stored dates from expressions
    /// that happen to sit in the stored title or description.
    @ObservationIgnored private var isApplying = false

    public init(
        itemId: UUIDv7,
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        contactRepository: (any ContactRepository)? = nil,
        activityRepository: (any ActivityRepository)? = nil,
        reminderRepository: (any ReminderRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        onClosed: (@MainActor () -> Void)? = nil
    ) {
        self.itemId = itemId
        self.repository = repository
        self.linkRepository = linkRepository
        self.attachmentRepository = attachmentRepository
        self.contactRepository = contactRepository
        self.activityRepository = activityRepository
        self.reminderRepository = reminderRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
        self.onClosed = onClosed
    }

    // MARK: Loading

    /// Loads the item and every section the window shows. Idempotent — the
    /// view calls it on appear, and the actions call it after each write.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        guard let loaded = await repository.item(itemId) else {
            item = nil
            return
        }

        item = loaded
        status = loaded.status
        isApplying = true
        edit = DetailEdit(item: loaded)
        isApplying = false

        await reloadRelated()
    }

    /// Picks up a summary written in the background (email capture) without
    /// overwriting a summary the user has started editing.
    public func refreshSummaryIfEmpty() async {
        guard let current = item,
              edit.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let latest = await repository.item(current.id),
              !latest.summary.isEmpty
        else { return }
        item = latest
        edit.summary = latest.summary
    }

    /// Refreshes the sections that depend on other items: attachments,
    /// children, links, parent, and the progress roll-up — and re-derives the
    /// presentation status from the current blockers.
    private func reloadRelated() async {
        guard let item = item else { return }

        async let loadedAttachments = attachmentRepository.attachments(for: item.id)
        async let loadedChildren = repository.children(of: item.id)
        async let linksTo = linkRepository.links(to: item.id)
        async let linksFrom = linkRepository.links(from: item.id)
        async let loadedAllItems = repository.allItems()
        let (atts, kids, toLinks, fromLinks, allItems) =
            await (loadedAttachments, loadedChildren, linksTo, linksFrom, loadedAllItems)

        attachments = atts
        if let contactRepository {
            contacts = await contactRepository.contacts(forTask: item.id)
            allContacts = await contactRepository.contacts()
        } else {
            contacts = []
            allContacts = []
        }
        children = kids
        linkCandidates = allItems
            .filter { $0.id != item.id && !$0.isDeleted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let blockerLinks = toLinks.filter { $0.kind == .blocks }
        let blockingLinks = fromLinks.filter { $0.kind == .blocks }
        let relatedLinks = (toLinks + fromLinks).filter { $0.kind == .relatesTo }

        var referenced = Set<UUIDv7>()
        for link in blockerLinks { referenced.insert(link.fromId) }
        for link in blockingLinks { referenced.insert(link.toId) }
        for link in relatedLinks {
            referenced.insert(link.fromId)
            referenced.insert(link.toId)
        }
        if let parentId = item.parentId { referenced.insert(parentId) }
        referenced.remove(item.id)

        var byId: [UUIDv7: WorkItem] = [:]
        await withTaskGroup(of: (UUIDv7, WorkItem?).self) { group in
            for id in referenced {
                group.addTask { [repository] in (id, await repository.item(id)) }
            }
            for await (id, resolved) in group {
                if let resolved { byId[id] = resolved }
            }
        }

        blockers = blockerLinks.compactMap { byId[$0.fromId] }
        blockings = blockingLinks.compactMap { byId[$0.toId] }
        related = relatedLinks.compactMap { byId[$0.fromId] ?? byId[$0.toId] }
        parent = item.parentId.flatMap { byId[$0] }

        displayStatus = StatusDeriver().derive(stored: item.status, blockers: blockers)
        progress = await RollUpProgress(repository: repository).execute(item.id)
        if let activityRepository {
            activity = await activityRepository.events(for: item.id)
        }
        if let reminderRepository {
            reminder = await reminderRepository.reminder(for: item.id, kind: .task)
            reminderDate = reminder?.fireAt ?? defaultReminderDate(for: item)
        }
    }

    private func defaultReminderDate(for item: WorkItem) -> Date {
        let now = clock()
        let proposed = item.endAt.addingTimeInterval(-30 * 60)
        return proposed > now ? proposed : now.addingTimeInterval(15 * 60)
    }

    /// Sets (or replaces) this task's custom reminder and asks the app to
    /// reschedule notifications immediately.
    public func setReminder(at date: Date) async {
        guard let item, let reminderRepository else { return }
        guard date > clock() else {
            lastError = "Choose a reminder time in the future."
            return
        }
        do {
            let value = Reminder(
                id: reminder?.id ?? .new(),
                itemId: item.id,
                kind: .task,
                fireAt: date,
                createdAt: clock()
            )
            try await reminderRepository.save(value)
            reminder = value
            reminderDate = date
            lastSavedAt = clock()
            NotificationCenter.default.post(name: TodayFlowEvents.remindersChanged, object: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func clearReminder() async {
        guard let reminder, let reminderRepository else { return }
        do {
            try await reminderRepository.delete(reminder.id)
            self.reminder = nil
            if let item { reminderDate = defaultReminderDate(for: item) }
            NotificationCenter.default.post(name: TodayFlowEvents.remindersChanged, object: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Persistence

    /// Persists the edited fields (FR-22: inline edits commit on interaction).
    ///
    /// A no-op when nothing changed, so the view can call it on every
    /// interaction (title submit, date-picker change, focus loss) without
    /// bumping the version.
    /// Corrects the title, summary, and description in one pass. The AI is
    /// optional: failures leave every field untouched.
    public func correctDraftText() async {
        guard let corrector, !isCorrectingText else { return }
        let title = edit.title
        let summary = edit.summary
        let description = edit.descriptionMd
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        isCorrectingText = true
        lastError = nil
        defer { isCorrectingText = false }
        do {
            async let correctedTitle: String = title.isEmpty
                ? title
                : corrector.correctText(title)
            async let correctedSummary: String = summary.isEmpty
                ? summary
                : corrector.correctText(summary)
            async let correctedDescription: String = description.isEmpty
                ? description
                : corrector.correctText(description)
            let (newTitle, newSummary, newDescription) = try await (
                correctedTitle,
                correctedSummary,
                correctedDescription
            )
            if !newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                edit.title = newTitle
            }
            if !newSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                edit.summary = newSummary
            }
            if !newDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                edit.descriptionMd = newDescription
            }
            await commit()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func addContact(_ contactId: UUIDv7) async {
        guard let item, let contactRepository else { return }
        do {
            try await contactRepository.addContact(contactId, toTask: item.id)
            contacts = await contactRepository.contacts(forTask: item.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Creates a contact from the task detail (or links an existing one with
    /// the same email/phone) and immediately associates it with this task.
    @discardableResult
    public func createAndLinkContact(
        firstName: String,
        lastName: String = "",
        email: String = "",
        phone: String = ""
    ) async -> Contact? {
        guard let item, let contactRepository else { return nil }
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty || !last.isEmpty || !mail.isEmpty || !number.isEmpty
        else { return nil }

        do {
            let existing = await contactRepository.contacts()
            let emailKey = mail.lowercased()
            let phoneKey = number.filter(\.isNumber)
            if let match = existing.first(where: { candidate in
                (!emailKey.isEmpty && candidate.canonicalEmails.contains(emailKey))
                    || (!phoneKey.isEmpty
                        && candidate.canonicalPhones.contains(phoneKey))
            }) {
                try await contactRepository.addContact(match.id, toTask: item.id)
                contacts = await contactRepository.contacts(forTask: item.id)
                allContacts = await contactRepository.contacts()
                return match
            }

            let now = clock()
            let contact = Contact(
                firstName: first,
                lastName: last,
                emails: mail.isEmpty ? [] : [mail],
                phones: number.isEmpty ? [] : [number],
                source: "manual",
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId
            )
            try await contactRepository.save(contact)
            try await contactRepository.addContact(contact.id, toTask: item.id)
            contacts = await contactRepository.contacts(forTask: item.id)
            allContacts = await contactRepository.contacts()
            return contact
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    public func removeContact(_ contactId: UUIDv7) async {
        guard let item, let contactRepository else { return }
        do {
            try await contactRepository.removeContact(contactId, fromTask: item.id)
            contacts = await contactRepository.contacts(forTask: item.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func commit() async {
        guard let current = item, !isSaving else { return }

        let trimmed = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Title can't be empty."
            return
        }

        let unchanged = trimmed == current.title
            && edit.descriptionMd == current.descriptionMd
            && edit.summary == current.summary
            && edit.startAt == current.startAt
            && edit.endAt == current.endAt
            && edit.estimatedMinutes == current.estimatedMinutes
        guard !unchanged else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        let now = clock()
        var updated = current
        updated.title = trimmed
        updated.descriptionMd = edit.descriptionMd
        updated.summary = edit.summary
        updated.startAt = edit.startAt
        updated.endAt = edit.endAt
        updated.estimatedMinutes = edit.estimatedMinutes
        updated = updated.touching(now)
        updated.deviceId = deviceId

        do {
            try await repository.save(updated)
            item = updated
            lastSavedAt = now
            await reloadRelated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Actions

    /// Completes the item (FR-14). Refuses while a prerequisite is open
    /// unless `force` is set (the "override with a confirmation" path).
    public func complete(force: Bool = false) async {
        await commit()
        guard let item = item, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        do {
            let updated = try await CompleteTask(
                repository: repository,
                linkRepository: linkRepository,
                deviceId: deviceId
            ).execute(item.id, at: clock(), force: force)
            self.item = updated
            status = updated.status
            lastSavedAt = clock()
            await reloadRelated()
        } catch CompleteTask.Error.blocked {
            let names = blockers.map(\.title).joined(separator: ", ")
            lastError = names.isEmpty ? "This item is blocked." : "Blocked by: \(names)"
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Changes the stored status (FR-20 status pill). `.done` routes through
    /// `CompleteTask` so the blocker guard applies; `.blocked` is derived and
    /// never stored, so it is ignored.
    public func setStatus(_ newStatus: Status) async {
        await commit()
        guard let item = item, !isSaving else { return }
        guard newStatus != .blocked, newStatus != item.status else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        do {
            let updated: WorkItem
            if newStatus == .done {
                updated = try await CompleteTask(
                    repository: repository,
                    linkRepository: linkRepository,
                    deviceId: deviceId
                ).execute(item.id, at: clock())
            } else {
                updated = try await SetStatus(repository: repository, deviceId: deviceId)
                    .execute(item.id, to: newStatus, at: clock())
            }
            self.item = updated
            status = updated.status
            lastSavedAt = clock()
            await reloadRelated()
        } catch CompleteTask.Error.blocked {
            let names = blockers.map(\.title).joined(separator: ", ")
            lastError = names.isEmpty ? "This item is blocked." : "Blocked by: \(names)"
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Changes the priority (FR-20 priority pill).
    public func setPriority(_ priority: Priority) async {
        await commit()
        guard let item = item, !isSaving else { return }
        guard priority != item.priority else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        do {
            let updated = try await SetPriority(repository: repository, deviceId: deviceId)
                .execute(item.id, to: priority, at: clock())
            self.item = updated
            lastSavedAt = clock()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Moves the due time to the next working day's EOB (FR-42/43).
    public func moveToTomorrow() async {
        await commit()
        guard let item = item, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        do {
            let updated = try await MoveToTomorrow(
                repository: repository,
                calendar: calendar,
                deviceId: deviceId
            ).execute(item.id, at: clock())
            self.item = updated
            isApplying = true
            edit.endAt = updated.endAt
            isApplying = false
            lastSavedAt = clock()
            await reloadRelated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Soft-deletes the item (FR-32), reconnecting any dependency chain it
    /// sat in the middle of, then asks the host to close the window.
    public func delete() async {
        await commit()
        guard let item = item, !isSaving else { return }

        isSaving = true
        defer { isSaving = false }
        lastError = nil

        do {
            _ = try await DeleteTask(
                itemRepository: repository,
                linkRepository: linkRepository,
                deviceId: deviceId
            ).execute(item.id, at: clock())
            self.item = nil
            isDeleted = true
            onClosed?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Links (driver.md FR-30)

    /// Adds a `.blocks` or `.relatesTo` link through the Core use case, which
    /// enforces the linked-list shape and rejects cycles.
    public func addLink(to otherId: UUIDv7, kind: ItemLink.Kind) async {
        guard let item, otherId != item.id else { return }
        do {
            let from = kind == .blocks ? otherId : item.id
            let to = kind == .blocks ? item.id : otherId
            try await LinkTasks(
                linkRepository: linkRepository,
                itemRepository: repository,
                deviceId: deviceId
            ).execute(from: from, to: to, kind: kind, at: clock())
            lastSavedAt = clock()
            await reloadRelated()
        } catch LinkTasks.Error.wouldCreateLoop {
            lastError = "This would create a loop."
        } catch LinkTasks.Error.chainFull {
            lastError = "One of these tasks already has a chain neighbour."
        } catch LinkTasks.Error.duplicate {
            lastError = "These tasks are already linked."
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: AI breakdown (driver.md §8)

    /// Asks the AI for a set of subtasks. The result is shown for approval and
    /// thrown away if the user dismisses it.
    public func requestBreakdown() async {
        guard let assistant, let item, !isSuggestingSubtasks else { return }
        isSuggestingSubtasks = true
        defer { isSuggestingSubtasks = false }
        lastError = nil

        do {
            subtaskSuggestions = try await assistant.breakDown(item)
        } catch {
            subtaskSuggestions = []
            lastError = error.localizedDescription
        }
    }

    /// Creates the chosen suggestions as children of the current item. Existing
    /// items are untouched; AI output still requires this explicit approval.
    public func addSubtasks(_ suggestions: [SubtaskSuggestion]) async {
        guard let item, !suggestions.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        lastError = nil

        let kind: WorkItem.Kind
        let parentId: UUIDv7?
        switch item.kind {
        case .epic:
            kind = .project
            parentId = item.id
        case .project:
            kind = .task
            parentId = item.id
        case .task:
            kind = .subtask
            parentId = item.id
        case .subtask:
            kind = .subtask
            parentId = item.parentId
        }

        let create = CreateTask(
            repository: repository,
            calendar: calendar,
            deviceId: deviceId
        )
        do {
            for suggestion in suggestions {
                var description = suggestion.details
                if let minutes = suggestion.estimatedMinutes {
                    description += description.isEmpty ? "" : "\n\n"
                    description += "Estimated: \(minutes) min"
                }
                try await create.execute(
                    CreateTask.Input(
                        kind: kind,
                        title: suggestion.title,
                        descriptionMd: description,
                        parentId: parentId,
                        startAt: clock(),
                        priority: item.priority
                    )
                )
            }
            subtaskSuggestions = []
            lastSavedAt = clock()
            await reloadRelated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Closes the suggestion list without creating anything.
    public func dismissSubtaskSuggestions() {
        subtaskSuggestions = []
    }

    // MARK: Tags

    public func addTag(_ text: String) async {
        guard var item else { return }
        let tag = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              !item.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        else { return }

        item.tags.append(tag)
        item = item.touching(clock())
        item.deviceId = deviceId
        do {
            try await repository.save(item)
            self.item = item
            lastSavedAt = clock()
            await reloadRelated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func removeTag(_ tag: String) async {
        guard var item, item.tags.contains(tag) else { return }
        item.tags.removeAll { $0 == tag }
        item = item.touching(clock())
        item.deviceId = deviceId
        do {
            try await repository.save(item)
            self.item = item
            lastSavedAt = clock()
            await reloadRelated()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves a user description for one attached object.
    public func updateAttachmentNote(_ id: UUIDv7, note: String) async {
        guard let index = attachments.firstIndex(where: { $0.id == id })
        else { return }
        var attachment = attachments[index]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        attachment.note = trimmed.isEmpty ? nil : trimmed
        do {
            try await attachmentRepository.save(attachment)
            attachments[index] = attachment
            lastSavedAt = clock()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Removes an attachment from the item.
    public func removeAttachment(_ id: UUIDv7) async {
        guard let item = item else { return }
        do {
            try await attachmentRepository.delete(id)
            attachments = await attachmentRepository.attachments(for: item.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Date shortcuts (FR-22)

    /// Applies a compact date shortcut to the due time, then persists it.
    public func applyDateShortcut(_ shortcut: DateShortcut) async {
        guard item != nil else { return }

        let now = clock()
        let cal = calendar.calendar
        switch shortcut {
        case .todayEOB:
            edit.endAt = calendar.endOfBusiness(for: now)
        case .tomorrowEOB:
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
                edit.endAt = calendar.endOfBusiness(for: tomorrow)
            }
        case .plusOneHour:
            edit.endAt = edit.endAt.addingTimeInterval(3600)
        case .nextMonday:
            // The next Monday strictly after `now` (a Monday "now" means the
            // following week), at the business start.
            let weekday = cal.component(.weekday, from: now)
            var daysAhead = (2 - weekday + 7) % 7
            if daysAhead == 0 { daysAhead = 7 }
            if let monday = cal.date(byAdding: .day, value: daysAhead, to: now) {
                edit.endAt = calendar.startOfBusiness(for: monday)
            }
        }

        await commit()
    }

    // MARK: Natural-language dates

    /// Re-resolves NL dates after a title/description keystroke (FR-05): the
    /// title first, then the description; manual dates survive when no
    /// expression is found. Mirrors `CaptureViewModel.reparseDates`.
    private func reparseDates() {
        let now = clock()
        let parser = ParseNaturalLanguageDates(calendar: calendar.calendar, workCalendar: calendar)
        if let hit = parser.parse(edit.title, at: now).first {
            edit.startAt = hit.start
            edit.endAt = hit.end
        } else if let hit = parser.parse(edit.descriptionMd, at: now).first {
            edit.startAt = hit.start
            edit.endAt = hit.end
        }
    }
}
