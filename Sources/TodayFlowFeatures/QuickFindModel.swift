import Foundation
import Observation
import TodayFlowCore

/// Tasks opened recently on this Mac, newest first (Quick Find's empty state).
public enum RecentTasks {
    static let key = "todayflow.recentTasks"
    static let limit = 30

    public static func record(_ id: UUIDv7, defaults: UserDefaults = .standard) {
        var ids = list(defaults: defaults).filter { $0 != id }
        ids.insert(id, at: 0)
        defaults.set(ids.prefix(limit).map(\.uuid.uuidString), forKey: key)
    }

    public static func list(defaults: UserDefaults = .standard) -> [UUIDv7] {
        (defaults.stringArray(forKey: key) ?? []).compactMap { UUID(uuidString: $0).map(UUIDv7.init) }
    }
}

/// Quick Find: type to find any task; ↑↓ to pick; ↩ open, ⌘↩ done,
/// ⌥↩ do today. `#` `@` `/` offer completions for tags, people, projects.
@MainActor
@Observable
public final class QuickFindModel {
    public var text = "" {
        didSet {
            guard text != oldValue else { return }
            refresh()
        }
    }
    public private(set) var results: [QuickFindResult] = []
    /// The highlighted row; `results.count` means the "Ask AI" row.
    public var selection = 0
    public private(set) var isLoading = false
    public private(set) var flash: String?

    @ObservationIgnored private var records: [TaskSearchRecord] = []
    @ObservationIgnored private var knownTags: [String] = []
    @ObservationIgnored private var knownContacts: [String] = []
    @ObservationIgnored private var knownProjects: [String] = []

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let linkRepository: any LinkRepository
    @ObservationIgnored private let attachmentRepository: any AttachmentRepository
    @ObservationIgnored private let actionRepository: (any ActionItemRepository)?
    @ObservationIgnored private let contactRepository: (any ContactRepository)?
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let recent: @MainActor () -> [UUIDv7]

    @ObservationIgnored public var onOpen: (@MainActor (UUIDv7) -> Void)?
    @ObservationIgnored public var onAsk: (@MainActor (String) -> Void)?
    @ObservationIgnored public var onClose: (@MainActor () -> Void)?

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        actionRepository: (any ActionItemRepository)? = nil,
        contactRepository: (any ContactRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        recent: @escaping @MainActor () -> [UUIDv7] = { RecentTasks.list() }
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.attachmentRepository = attachmentRepository
        self.actionRepository = actionRepository
        self.contactRepository = contactRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
        self.recent = recent
    }

    // MARK: - Loading and searching

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        records = await TaskSearchLoader.load(
            repository: repository,
            attachmentRepository: attachmentRepository,
            actionRepository: actionRepository,
            contactRepository: contactRepository
        )
        let live = records.filter { !$0.item.isDeleted }
        knownTags = Self.byUse(live.filter { $0.item.kind != .project }.flatMap(\.item.tags))
        knownContacts = Self.byUse(live.flatMap(\.contactNames))
        knownProjects = live.filter { $0.item.kind == .project }.map(\.item.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        refresh()
    }

    private static func byUse(_ values: [String]) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for value in values { counts[value.lowercased(), default: (value, 0)].count += 1 }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }.map(\.name)
    }

    public var query: QuickFindQuery { .parse(text) }

    /// "Recent" when nothing is typed, else "Tasks".
    public var heading: String { query.isEmpty ? "Recent and due now" : "\(results.count) found" }

    /// The "Ask AI" row shows when free words are typed and Ask is wired.
    public var showsAskRow: Bool {
        onAsk != nil && !query.words.isEmpty
    }

    public func refresh() {
        results = QuickFind.search(
            records, query: query, recent: recent(), now: clock(), calendar: calendar.calendar
        )
        selection = min(selection, max(0, results.count - 1))
        if text.isEmpty { selection = 0 }
    }

    // MARK: - Completions for # @ /

    public struct Completion: Hashable, Identifiable {
        public var label: String
        public var insert: String
        public var id: String { insert }
    }

    /// Suggestions for the word being typed, when it starts with # @ or /.
    public var completions: [Completion] {
        guard !text.hasSuffix(" "),
              let last = text.split(separator: " ", omittingEmptySubsequences: false).last,
              let first = last.first, "#@/".contains(first)
        else { return [] }
        let typed = last.dropFirst().lowercased()
        let pool: [String]
        switch first {
        case "#": pool = knownTags
        case "@": pool = knownContacts
        default: pool = knownProjects
        }
        return pool
            .filter { typed.isEmpty || $0.lowercased().contains(typed) }
            // Already typed in full: Return should open, not complete.
            .filter { $0.lowercased().replacingOccurrences(of: " ", with: "-") != typed }
            .prefix(8)
            .map { value in
                let token = value.contains(" ") ? value.replacingOccurrences(of: " ", with: "-") : value
                return Completion(label: "\(first)\(value)", insert: "\(first)\(token)")
            }
    }

    public func complete(_ completion: Completion) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !words.isEmpty { words.removeLast() }
        words.append(completion.insert)
        text = words.joined(separator: " ") + " "
    }

    /// Adds a filter word ("due:today") to the search.
    public func insertFilter(_ token: String) {
        let base = text.trimmingCharacters(in: .whitespaces)
        text = (base.isEmpty ? "" : base + " ") + token + " "
    }

    // MARK: - Keyboard

    public func move(_ delta: Int) {
        let last = results.count - 1 + (showsAskRow ? 1 : 0)
        guard last >= 0 else { return }
        selection = min(max(selection + delta, 0), last)
    }

    private var selectedResult: QuickFindResult? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    /// ↩: opens the highlighted task, or asks AI on the Ask row.
    public func activate() {
        if let result = selectedResult {
            open(result.id)
        } else if showsAskRow {
            ask()
        }
    }

    public func open(_ id: UUIDv7) {
        onOpen?(id)
        onClose?()
    }

    public func ask() {
        let question = text.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        onAsk?(question)
        onClose?()
    }

    // MARK: - Actions

    /// ⌘↩: marks the highlighted task done.
    public func completeSelected() async {
        guard let result = selectedResult, !result.item.status.isTerminal else { return }
        do {
            _ = try await CompleteTask(
                repository: repository, linkRepository: linkRepository,
                deviceId: deviceId, calendar: calendar.calendar
            ).execute(result.id, at: clock())
            flash = "Done: \(result.item.title)"
        } catch CompleteTask.Error.blocked {
            flash = "“\(result.item.title)” is waiting on another task"
        } catch {
            flash = "Couldn’t complete: \(error.localizedDescription)"
        }
        await load()
    }

    /// ⌥↩: puts the highlighted task on today's list (starts now; a past
    /// due time moves to the end of today).
    public func doTodaySelected() async {
        guard let result = selectedResult, var item = await repository.item(result.id),
              !item.status.isTerminal
        else { return }
        let now = clock()
        item.startAt = now
        if item.endAt <= now {
            item.endAt = max(calendar.endOfBusiness(for: now), now.addingTimeInterval(TaskSchedule.minimumDuration))
        }
        item = item.touching(now)
        item.deviceId = deviceId
        do {
            try await repository.save(item)
            flash = "On today: \(item.title)"
        } catch {
            flash = "Couldn’t move it: \(error.localizedDescription)"
        }
        await load()
    }
}
