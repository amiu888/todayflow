import Foundation
import Observation
import TodayFlowCore

/// A presentation action fired by a Today row (driver.md FR-12, FR-31).
///
/// Declared here — with the ViewModel, not in `TaskRowView` — so the row and
/// the ViewModel share one contract without the view file owning it.
public enum TaskRowQuickAction: Hashable, Sendable {
    /// Change the item's priority.
    case setPriority(Priority)
    /// Reschedule the item to the next working day (driver.md FR-12).
    case moveToTomorrow
    /// Open the item in the detail view.
    case open
}

extension TaskRowModel {
    /// A copy with a different `hasChainBelow` flag.
    ///
    /// The model is immutable; the ViewModel derives the chain from the
    /// *visible* order after filtering/sorting, so it can't be baked in at
    /// row-build time.
    func replacing(hasChainBelow: Bool) -> TaskRowModel {
        TaskRowModel(
            id: id,
            title: title,
            priority: priority,
            isDone: isDone,
            isBlocked: isBlocked,
            dueAt: dueAt,
            isOverdue: isOverdue,
            completedAt: completedAt,
            attachments: attachments,
            attachmentCount: attachmentCount,
            parentColorHex: parentColorHex,
            hasChainBelow: hasChainBelow
        )
    }
}

/// ViewModel for the Today panel (driver.md FR-10…FR-15, FR-31).
///
/// Owns the day's items, the derived row models, and the filter/sort/search
/// state; routes row interactions through the Core use cases. The container
/// view renders `visibleOverdueRows` / `visibleOpenRows` / `visibleDoneRows`
/// plus the leaf views (header, chips, rows).
///
/// Concurrency: `@MainActor` — all state mutation happens on the main actor;
/// repository reads fan out off it via `async let` / task groups.
///
/// Usage from the container view:
///
///     .task { await model.observe() }   // initial load + live updates
@MainActor
@Observable
public final class TodayViewModel {

    // MARK: Observed state

    /// The day's items + progress, as produced by `TodayQuery`.
    public private(set) var result: TodayQuery.Result = .empty

    /// All links (drives blocked + chain state for the day's items).
    private var links: [ItemLink] = []

    /// Attachments keyed by item id (drives the row's icon cluster).
    private var attachments: [UUIDv7: [Attachment]] = [:]

    /// Referenced parents / blocker prerequisites that are not on today's list.
    private var extraItems: [UUIDv7: WorkItem] = [:]
    /// Every live item, for project-ancestry filtering (FR-15).
    private var allItemsById: [UUIDv7: WorkItem] = [:]

    public var filter: TodayFilter = .all
    public var sort: TodaySort = .manual
    public var searchText: String = ""
    /// FR-15 "by project": `nil` means all projects.
    public var projectFilter: UUIDv7?
    /// Projects offered by the filter menu.
    public private(set) var projects: [WorkItem] = []

    /// The row selected by a single tap (drives ⌥↑/⌥↓ reordering, FR-12).
    public var selectedId: UUIDv7?

    /// The most recent completion, for the 5-second Undo affordance (FR-14).
    public struct CompletionUndo: Hashable, Sendable {
        public let id: UUIDv7
        public let previousStatus: Status

        public init(id: UUIDv7, previousStatus: Status) {
            self.id = id
            self.previousStatus = previousStatus
        }
    }
    public private(set) var completionUndo: CompletionUndo?

    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    // MARK: Dependencies (never observed)

    @ObservationIgnored private var repository: any WorkItemRepository
    @ObservationIgnored private var linkRepository: any LinkRepository
    @ObservationIgnored private var attachmentRepository: any AttachmentRepository
    /// Optional, so the view model works without a settings store (the choice
    /// simply is not persisted — FR-11).
    @ObservationIgnored private var settingRepository: (any SettingRepository)?
    @ObservationIgnored private var calendar: WorkCalendar
    @ObservationIgnored private var deviceId: String
    @ObservationIgnored private var clock: @Sendable () -> Date
    @ObservationIgnored public var onOpenTask: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        settingRepository: (any SettingRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.attachmentRepository = attachmentRepository
        self.settingRepository = settingRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
        self.onOpenTask = onOpenTask
    }

    // MARK: Loading

    /// Reloads the day: items, progress, links, attachments, and the
    /// referenced parents / blocker prerequisites. Idempotent.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        // Restore the persisted sort choice (FR-11: "Choice is persisted")
        // before the rows are derived.
        if let settingRepository,
           let raw = await settingRepository.value(for: SettingKeys.todaySort),
           let saved = TodaySort(rawValue: raw) {
            sort = saved
        }

        let now = clock()
        let day = calendar.calendar.startOfDay(for: now)
        let query = TodayQuery(repository: repository, calendar: calendar)

        async let dayResult = query.execute(on: day, at: now)
        async let loadedLinks = linkRepository.allLinks()
        async let loadedItems = repository.allItems()
        let (r, allLinks, allItems) = await (dayResult, loadedLinks, loadedItems)

        self.result = r
        self.links = allLinks
        Diagnostics.log("today", "load open=\(r.all.count) done=\(r.doneToday.count) filter=\(filter.rawValue)")
        self.allItemsById = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        self.projects = allItems
            .filter { $0.kind == .project && !$0.isDeleted }
            .sorted {
                if $0.displayOrder != $1.displayOrder {
                    return FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder)
                }
                return $0.title < $1.title
            }

        // Resolve references that are not on today's list: parents (color
        // strip) and blocker prerequisites (the lock).
        var known: [UUIDv7: WorkItem] = [:]
        for item in r.all + r.doneToday { known[item.id] = item }

        var needed: Set<UUIDv7> = []
        for item in r.all + r.doneToday {
            if let parentId = item.parentId, known[parentId] == nil {
                needed.insert(parentId)
            }
        }
        for link in allLinks where link.kind == .blocks {
            if known[link.toId] != nil, known[link.fromId] == nil {
                needed.insert(link.fromId)
            }
        }

        var fetched: [UUIDv7: WorkItem] = [:]
        await withTaskGroup(of: (UUIDv7, WorkItem?).self) { group in
            for id in needed {
                group.addTask { [repository] in (id, await repository.item(id)) }
            }
            for await (id, item) in group {
                if let item { fetched[id] = item }
            }
        }
        self.extraItems = fetched

        var loadedAttachments: [UUIDv7: [Attachment]] = [:]
        await withTaskGroup(of: (UUIDv7, [Attachment]).self) { group in
            for id in known.keys {
                group.addTask { [attachmentRepository] in
                    (id, await attachmentRepository.attachments(for: id))
                }
            }
            for await (id, list) in group {
                loadedAttachments[id] = list
            }
        }
        self.attachments = loadedAttachments
    }

    /// Live updates: consumes `observeToday` and reloads on every emission.
    ///
    /// The first stream emission performs the initial load, so the container
    /// view needs only `.task { await model.observe() }`. When the calendar
    /// day rolls over, re-subscribes for the new day.
    public func observe() async {
        while !Task.isCancelled {
            let day = calendar.calendar.startOfDay(for: clock())
            let stream = await repository.observeToday(on: day, calendar: calendar)
            for await _ in stream {
                if calendar.calendar.startOfDay(for: clock()) != day { break }
                await load()
            }
        }
    }

    // MARK: Derived rows

    /// Progress for the header (worker's `ProgressHeaderView`).
    public var progress: TodayQuery.Progress { result.progress }

    /// Every item the day references: open + done + fetched extras.
    private var knownItems: [UUIDv7: WorkItem] {
        var dict = extraItems
        for item in result.all + result.doneToday { dict[item.id] = item }
        return dict
    }

    /// Open items (overdue + on-time) as row models, in the current display order.
    public var openRows: [TaskRowModel] {
        let known = knownItems
        let now = clock()
        return result.all.map { makeRow($0, now: now, known: known) }
    }

    /// Items completed today, as row models (the "Done today" section).
    public var doneRows: [TaskRowModel] {
        let known = knownItems
        let now = clock()
        return result.doneToday.map { makeRow($0, now: now, known: known) }
    }

    /// Open rows after filter + search + sort, with the overdue group pinned
    /// on top (FR-10) and chain connectors derived for adjacent rows (FR-31).
    public var visibleRows: [TaskRowModel] {
        let sorted = applySort(openRows.filter { matches($0) })
        let overdue = sorted.filter(\.isOverdue)
        let onTime = sorted.filter { !$0.isOverdue }
        return withChains(overdue + onTime)
    }

    /// The pinned "Overdue" section.
    public var visibleOverdueRows: [TaskRowModel] {
        visibleRows.filter(\.isOverdue)
    }

    /// The "Today" section (open, on-time).
    public var visibleOpenRows: [TaskRowModel] {
        visibleRows.filter { !$0.isOverdue }
    }

    /// The "Done today" section (kept in the repository's completion order).
    public var visibleDoneRows: [TaskRowModel] {
        doneRows.filter { matches($0) }
    }

    private func makeRow(_ item: WorkItem, now: Date, known: [UUIDv7: WorkItem]) -> TaskRowModel {
        let isDone = item.status.isComplete
        let blockerItems = links
            .filter { $0.kind == .blocks && $0.toId == item.id }
            .compactMap { known[$0.fromId] }
        let isBlocked = !isDone
            && StatusDeriver().derive(stored: item.status, blockers: blockerItems) == .blocked
        let isOverdue = !isDone && item.endAt < now
        let itemAttachments = attachments[item.id] ?? []

        return TaskRowModel(
            id: item.id,
            title: item.title,
            priority: item.priority,
            isDone: isDone,
            isBlocked: isBlocked,
            dueAt: item.endAt,
            isOverdue: isOverdue,
            completedAt: item.completedAt,
            attachments: itemAttachments.prefix(3).map {
                TaskRowModel.AttachmentHint(kind: $0.kind, displayName: $0.displayName)
            },
            attachmentCount: itemAttachments.count,
            parentColorHex: item.parentId.flatMap { known[$0]?.color },
            hasChainBelow: false
        )
    }

    // MARK: Filtering, search, sort

    private func matches(_ row: TaskRowModel) -> Bool {
        guard matchesFilter(row) else { return false }
        return matchesSearch(row)
    }

    private func matchesFilter(_ row: TaskRowModel) -> Bool {
        if let projectFilter,
           !belongsToProject(row.id, projectId: projectFilter)
        {
            return false
        }
        switch filter {
        case .all: return true
        case .blocked: return row.isBlocked
        case .p1p2: return row.priority <= .high
        }
    }

    /// Walks the parent chain so a task inside a project's subtasks still
    /// matches that project's filter.
    private func belongsToProject(_ itemId: UUIDv7, projectId: UUIDv7) -> Bool {
        var current: UUIDv7? = itemId
        var visited = Set<UUIDv7>()
        while let id = current, visited.insert(id).inserted {
            if id == projectId { return true }
            current = allItemsById[id]?.parentId
        }
        return false
    }

    private func matchesSearch(_ row: TaskRowModel) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if row.title.lowercased().contains(needle) { return true }
        if let item = knownItems[row.id],
           item.descriptionMd.lowercased().contains(needle) { return true }
        return (attachments[row.id] ?? []).contains {
            $0.displayName.lowercased().contains(needle)
        }
    }

    private func applySort(_ rows: [TaskRowModel]) -> [TaskRowModel] {
        switch sort {
        case .manual:
            return rows
        case .priority:
            return rows.sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.dueAt < $1.dueAt
            }
        case .due:
            return rows.sorted {
                if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
                return $0.priority < $1.priority
            }
        }
    }

    /// Stamps `hasChainBelow` on each row whose successor in `rows` is a
    /// direct `.blocks` dependent (FR-31: completing A unlocks B).
    private func withChains(_ rows: [TaskRowModel]) -> [TaskRowModel] {
        guard rows.count > 1 else { return rows }
        var out = rows
        for index in 0..<(rows.count - 1) {
            let successor = rows[index + 1]
            let chained = links.contains {
                $0.kind == .blocks && $0.fromId == rows[index].id && $0.toId == successor.id
            }
            if chained {
                out[index] = rows[index].replacing(hasChainBelow: true)
            }
        }
        return out
    }

    // MARK: Actions

    /// Completes the item, or reopens it if it is done (FR-14).
    public func toggle(_ id: UUIDv7) async {
        guard let item = await repository.item(id) else { return }
        let target: Status = item.status.isComplete ? .todo : .done
        let previous = item.status
        do {
            try await SetStatus(repository: repository, deviceId: deviceId)
                .execute(id, to: target, at: clock())
            completionUndo = target == .done
                ? CompletionUndo(id: id, previousStatus: previous)
                : nil
            if selectedId == id { selectedId = nil } // the row left its section
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reverts the most recent completion (FR-14: ⌘Z, and the 5-second bar).
    public func undoComplete() async {
        guard let undo = completionUndo else { return }
        do {
            try await SetStatus(repository: repository, deviceId: deviceId)
                .execute(undo.id, to: undo.previousStatus, at: clock())
            completionUndo = nil
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Sort + selection (driver.md FR-11, FR-12)

    /// Changes the sort and persists the choice (FR-11: "Choice is persisted").
    public func setSort(_ new: TodaySort) async {
        guard new != sort else { return }
        sort = new
        if let settingRepository {
            try? await settingRepository.set(new.rawValue, for: SettingKeys.todaySort)
        }
    }

    /// Selects a row; tapping the selected row again clears the selection.
    public func select(_ id: UUIDv7?) {
        selectedId = (selectedId == id) ? nil : id
    }

    // MARK: Manual reordering (driver.md FR-12)
    //
    // The Today list is a flat, cross-parent sequence, so the ViewModel
    // computes the new fractional-index key itself — from what the user sees
    // in `visibleRows` — and hands it to `ReorderTask` via `newDisplayOrder`,
    // which keeps each item's parent.
    //
    // A manual move implies the display order: if a non-manual sort is active,
    // it is switched off (and persisted) first, so the result is visible.

    /// Moves the selected row up / down by one in the visible sequence
    /// (⌥↑ / ⌥↓).
    public func moveUp(_ id: UUIDv7) async {
        await move(id, direction: .up)
    }

    public func moveDown(_ id: UUIDv7) async {
        await move(id, direction: .down)
    }

    /// Moves `id` to sit just before / after `targetId` in the visible
    /// sequence (drag & drop).
    public func move(_ id: UUIDv7, targetId: UUIDv7, before: Bool) async {
        guard id != targetId,
              let targetIndex = visibleRows.firstIndex(where: { $0.id == targetId }),
              let targetKey = displayKey(of: targetId)
        else { return }
        let boundId = before
            ? (targetIndex > 0 ? visibleRows[targetIndex - 1].id : nil)
            : (targetIndex < visibleRows.count - 1 ? visibleRows[targetIndex + 1].id : nil)
        let boundKey = boundId.flatMap { displayKey(of: $0) }
        let newKey = before
            ? FractionalIndex.midpoint(boundKey, targetKey)
            : FractionalIndex.midpoint(targetKey, boundKey)
        await applyManualMove(id, newKey: newKey)
    }

    private enum MoveDirection {
        case up
        case down
    }

    private func move(_ id: UUIDv7, direction: MoveDirection) async {
        let rows = visibleRows
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }

        // Insert *outside* the neighbour: moving up places the item between the
        // row above the neighbour (or the top) and the neighbour itself;
        // moving down between the neighbour and the row below it (or the end).
        let neighborIndex = direction == .up ? index - 1 : index + 1
        guard (0..<rows.count).contains(neighborIndex) else { return } // at an edge
        guard let neighborKey = displayKey(of: rows[neighborIndex].id) else { return }

        let newKey: String
        switch direction {
        case .up:
            let boundKey = index >= 2 ? displayKey(of: rows[index - 2].id) : nil
            newKey = FractionalIndex.midpoint(boundKey, neighborKey)
        case .down:
            let boundKey = index + 2 < rows.count ? displayKey(of: rows[index + 2].id) : nil
            newKey = FractionalIndex.midpoint(neighborKey, boundKey)
        }
        await applyManualMove(id, newKey: newKey)
    }

    /// The display-order key of a visible row (its underlying item).
    private func displayKey(of id: UUIDv7) -> String? {
        knownItems[id]?.displayOrder
    }

    private func applyManualMove(_ id: UUIDv7, newKey: String) async {
        if sort != .manual {
            await setSort(.manual)
        }
        do {
            try await ReorderTask(repository: repository, deviceId: deviceId)
                .execute(id, newDisplayOrder: newKey, at: clock())
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Handles a row quick action (FR-12, FR-31, detail open).
    public func quickAction(_ id: UUIDv7, _ action: TaskRowQuickAction) async {
        switch action {
        case .setPriority(let priority):
            do {
                try await SetPriority(repository: repository, deviceId: deviceId)
                    .execute(id, to: priority, at: clock())
                await load()
            } catch SetPriority.Error.unchanged {
                // Already at that priority — nothing to do.
            } catch {
                lastError = error.localizedDescription
            }
        case .moveToTomorrow:
            do {
                try await MoveToTomorrow(repository: repository, calendar: calendar, deviceId: deviceId)
                    .execute(id, at: clock())
                await load()
            } catch {
                lastError = error.localizedDescription
            }
        case .open:
            onOpenTask?(id)
        }
    }
}
