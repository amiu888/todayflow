import Foundation
import Observation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// Date filter presets for the All Tasks window.
public enum AllTasksDateFilter: String, CaseIterable, Identifiable, Sendable {
    case anyTime
    case past
    case today
    case last7Days
    case last30Days
    case next7Days
    case future
    case custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .anyTime: "Any time"
        case .past: "Past"
        case .today: "Today"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .next7Days: "Next 7 days"
        case .future: "Upcoming"
        case .custom: "Custom range"
        }
    }
}

/// Search, filter and history over every task, past and future.
@MainActor
@Observable
public final class AllTasksViewModel {
    public var searchText = "" { didSet { refresh() } }
    public var selectedTags: Set<String> = [] { didSet { refresh() } }
    public var scope: TaskSearchScope = .all { didSet { refresh() } }
    public var sort: TaskSearchSort = .newest { didSet { refresh() } }
    public var dateFilter: AllTasksDateFilter = .anyTime { didSet { refresh() } }
    public var customFrom: Date { didSet { refresh() } }
    public var customTo: Date { didSet { refresh() } }

    public private(set) var groups: [TaskSearchGroup] = []
    public private(set) var allTags: [String] = []
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false

    /// Distinct tasks shown (a task under two tags counts once).
    public var resultCount: Int {
        Set(groups.flatMap { $0.results.map(\.id) }).count
    }

    @ObservationIgnored private var records: [TaskSearchRecord] = []
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let attachmentRepository: any AttachmentRepository
    @ObservationIgnored private let actionRepository: (any ActionItemRepository)?
    @ObservationIgnored private let contactRepository: (any ContactRepository)?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        attachmentRepository: any AttachmentRepository,
        actionRepository: (any ActionItemRepository)? = nil,
        contactRepository: (any ContactRepository)? = nil,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { .now },
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.attachmentRepository = attachmentRepository
        self.actionRepository = actionRepository
        self.contactRepository = contactRepository
        self.calendar = calendar
        self.clock = clock
        self.onOpenDetail = onOpenDetail
        let now = clock()
        let today = calendar.startOfDay(for: now)
        self.customFrom = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        self.customTo = now
    }

    /// Loads every task and its searchable related text.
    public func load() async {
        isLoading = true
        defer { isLoading = false }

        async let itemsTask = repository.allItems()
        async let attachmentsTask = attachmentRepository.allAttachments()
        async let actionsTask = actionRepository?.allActions() ?? []
        let (items, attachments, actions) = await (itemsTask, attachmentsTask, actionsTask)

        var contactNames: [UUIDv7: [String]] = [:]
        if let contactRepository {
            for contact in await contactRepository.contacts() {
                for taskId in await contactRepository.taskIds(forContact: contact.id) {
                    contactNames[taskId, default: []].append(contact.displayName)
                }
            }
        }

        let attachmentsByItem = Dictionary(grouping: attachments, by: \.itemId)
        let actionsByItem = Dictionary(grouping: actions, by: \.itemId)
        records = items.map { item in
            TaskSearchRecord(
                item: item,
                attachments: attachmentsByItem[item.id] ?? [],
                actions: actionsByItem[item.id] ?? [],
                contactNames: contactNames[item.id] ?? []
            )
        }
        allTags = TaskSearch.allTags(in: records.filter { $0.item.kind != .project })
        // Drop selections for tags that no longer exist.
        let live = Set(allTags.map { $0.lowercased() })
        let kept = selectedTags.filter { live.contains($0.lowercased()) }
        if kept != selectedTags { selectedTags = kept }
        hasLoaded = true
        refresh()
    }

    public func toggleTag(_ tag: String) {
        if let existing = selectedTags.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            selectedTags.remove(existing)
        } else {
            selectedTags.insert(tag)
        }
    }

    public func isSelected(_ tag: String) -> Bool {
        selectedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public func clearFilters() {
        searchText = ""
        selectedTags = []
        scope = .all
        dateFilter = .anyTime
    }

    public var hasFilters: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
            || !selectedTags.isEmpty || scope != .all || dateFilter != .anyTime
    }

    /// The date range for the current preset, or `nil` for "Any time".
    public func dateRange() -> ClosedRange<Date>? {
        let now = clock()
        let today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)?
            .addingTimeInterval(-1) ?? now
        func daysFrom(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: today) ?? today
        }
        switch dateFilter {
        case .anyTime:
            return nil
        case .past:
            return Date.distantPast...today.addingTimeInterval(-1)
        case .today:
            return today...endOfToday
        case .last7Days:
            return daysFrom(-6)...endOfToday
        case .last30Days:
            return daysFrom(-29)...endOfToday
        case .next7Days:
            return today...(daysFrom(7).addingTimeInterval(-1))
        case .future:
            return daysFrom(1)...Date.distantFuture
        case .custom:
            let from = calendar.startOfDay(for: min(customFrom, customTo))
            let toDay = calendar.startOfDay(for: max(customFrom, customTo))
            let to = calendar.date(byAdding: .day, value: 1, to: toDay)?
                .addingTimeInterval(-1) ?? toDay
            return from...to
        }
    }

    private func refresh() {
        guard hasLoaded else { return }
        let query = TaskSearchQuery(
            text: searchText,
            tags: selectedTags,
            dateRange: dateRange(),
            scope: scope
        )
        groups = TaskSearch.run(records, query: query, sort: sort)
    }
}

public struct AllTasksView: View {
    @State private var model: AllTasksViewModel
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(model: AllTasksViewModel) {
        _model = State(initialValue: model)
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.allTags.isEmpty {
                tagBar
                Divider()
            }
            results
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(DesignTokens.Palette.background)
        .task {
            await model.load()
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.attachmentsChanged)) { _ in
            Task { await model.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.captureSaved)) { _ in
            Task { await model.load() }
        }
    }

    // MARK: Header

    @MainActor
    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                TextField(
                    "Search titles, notes, files, links, contacts… or #tag",
                    text: $model.searchText
                )
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
                .accessibilityIdentifier("all-tasks-search")
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }

            HStack(spacing: 10) {
                Picker("Status", selection: $model.scope) {
                    ForEach(TaskSearchScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show all, open, or closed tasks")

                Picker("Date", selection: $model.dateFilter) {
                    ForEach(AllTasksDateFilter.allCases) { filter in
                        if filter == .custom { Divider() }
                        Text(filter.label).tag(filter)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Only tasks whose start, due, or completion date falls in this range")

                if model.dateFilter == .custom {
                    DatePicker("From", selection: $model.customFrom, displayedComponents: .date)
                        .labelsHidden()
                    Text("–").foregroundStyle(.secondary)
                    DatePicker("To", selection: $model.customTo, displayedComponents: .date)
                        .labelsHidden()
                }

                Spacer(minLength: 0)

                Picker(selection: $model.sort) {
                    ForEach(TaskSearchSort.allCases, id: \.self) { sort in
                        Text(sort == .tag ? "Group by tag" : sort.label).tag(sort)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .fixedSize()
                .help("Sort results, or group them by tag")
            }
            .controlSize(.small)
        }
        .padding(14)
    }

    @MainActor
    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                ForEach(model.allTags, id: \.self) { tag in
                    let selected = model.isSelected(tag)
                    Button {
                        model.toggleTag(tag)
                    } label: {
                        Text("#\(tag)")
                            .font(.caption.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    selected
                                        ? DesignTokens.Palette.accent
                                        : DesignTokens.Palette.surfaceRaised
                                )
                            )
                            .foregroundStyle(selected ? Color.white : DesignTokens.Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help(selected ? "Stop filtering by #\(tag)" : "Only show tasks tagged #\(tag)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: Results

    @MainActor
    @ViewBuilder
    private var results: some View {
        if !model.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.groups.allSatisfy({ $0.results.isEmpty }) {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text(model.hasFilters ? "No matching tasks" : "No tasks yet")
                    .font(.body.weight(.medium))
                Text(
                    model.hasFilters
                        ? "Try fewer words, another date range, or fewer tags."
                        : "Tasks you create appear here, past and future."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if model.hasFilters {
                    Button("Clear filters") { model.clearFilters() }
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.groups) { group in
                            if model.sort == .tag {
                                Section {
                                    rows(group.results)
                                } header: {
                                    sectionHeader(group)
                                }
                            } else {
                                rows(group.results)
                            }
                        }
                    }
                    .padding(12)
                }
                Divider()
                HStack {
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.hasFilters {
                        Button("Clear filters") { model.clearFilters() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private var countLabel: String {
        let count = model.resultCount
        return count == 1 ? "1 task" : "\(count) tasks"
    }

    @MainActor
    private func sectionHeader(_ group: TaskSearchGroup) -> some View {
        HStack {
            Text(group.title)
                .font(.caption.weight(.bold))
            Text("\(group.results.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(DesignTokens.Palette.background)
    }

    @MainActor
    private func rows(_ results: [TaskSearchResult]) -> some View {
        ForEach(results) { result in
            AllTasksRow(
                result: result,
                colorScheme: colorScheme,
                isSelectedTag: { model.isSelected($0) },
                onTagTap: { model.toggleTag($0) }
            )
            .onTapGesture { model.onOpenDetail?(result.id) }
        }
    }
}

private struct AllTasksRow: View {
    let result: TaskSearchResult
    let colorScheme: ColorScheme
    let isSelectedTag: (String) -> Bool
    let onTagTap: (String) -> Void

    var body: some View {
        let item = result.item
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.status.symbolName)
                .foregroundStyle(item.status.isTerminal ? DesignTokens.Palette.success : PriorityColor.color(for: item.priority, in: colorScheme))
                .frame(width: 18)
                .padding(.top, 1)
                .help(item.status.label)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.status.isTerminal)
                    .foregroundStyle(item.status.isTerminal ? DesignTokens.Palette.textSecondary : DesignTokens.Palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        Button("#\(tag)") { onTagTap(tag) }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(isSelectedTag(tag) ? .bold : .regular))
                            .foregroundStyle(DesignTokens.Palette.accent)
                            .help("Filter by #\(tag)")
                    }
                    if !result.matchedFields.isEmpty {
                        Text("Found in " + result.matchedFields.map(\.label).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(dateCaption(for: item))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Text(item.priority.label)
                    .font(.caption2)
                    .foregroundStyle(PriorityColor.color(for: item.priority, in: colorScheme))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Palette.surface.opacity(0.7))
        )
        .contentShape(Rectangle())
        .help("Open \(item.title)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func dateCaption(for item: WorkItem) -> String {
        let format = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        if item.status.isTerminal, let completed = item.completedAt {
            return "\(item.status == .done ? "Done" : "Closed") \(completed.formatted(format))"
        }
        return "Due \(item.endAt.formatted(format))"
    }
}
