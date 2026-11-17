import Foundation
import Observation
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
import TodayFlowCore
import TodayFlowDesign

/// The quick filters at the top of the Task History window.
public enum TaskHistoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case dueToday
    case past
    case completed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: "All"
        case .dueToday: "Due today"
        case .past: "Past"
        case .completed: "Completed"
        }
    }
}

/// Every task in one list, newest date first, with a status filter and an
/// optional date range.
@MainActor
@Observable
public final class TaskHistoryViewModel {
    public struct DayGroup: Identifiable, Hashable, Sendable {
        public let day: Date
        public let items: [WorkItem]
        public var id: Date { day }
    }

    public var filter: TaskHistoryFilter = .all { didSet { refresh() } }
    /// When true, only tasks dated between `rangeFrom` and `rangeTo` show.
    public var usesDateRange = false { didSet { refresh() } }
    public var rangeFrom: Date { didSet { refresh() } }
    public var rangeTo: Date { didSet { refresh() } }

    public private(set) var groups: [DayGroup] = []
    public private(set) var counts: [TaskHistoryFilter: Int] = [:]
    public private(set) var isLoading = false
    public private(set) var hasLoaded = false

    public var resultCount: Int { groups.reduce(0) { $0 + $1.items.count } }

    @ObservationIgnored private var items: [WorkItem] = []
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { .now },
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
        self.onOpenDetail = onOpenDetail
        let today = calendar.startOfDay(for: clock())
        self.rangeFrom = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        self.rangeTo = today
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await repository.allItems()
            .filter { !$0.isDeleted && $0.kind == .task }
        hasLoaded = true
        refresh()
    }

    /// The date a task is listed under: when it was completed, else when it
    /// is due.
    public func listDate(_ item: WorkItem) -> Date {
        item.status.isComplete ? (item.completedAt ?? item.endAt) : item.endAt
    }

    public func isOverdue(_ item: WorkItem) -> Bool {
        !item.status.isTerminal && item.endAt < clock()
    }

    private func matches(_ item: WorkItem, _ filter: TaskHistoryFilter) -> Bool {
        let today = calendar.startOfDay(for: clock())
        switch filter {
        case .all:
            return true
        case .dueToday:
            return !item.status.isTerminal && calendar.isDate(item.endAt, inSameDayAs: today)
        case .past:
            return item.endAt < today
        case .completed:
            return item.status.isComplete
        }
    }

    private func inRange(_ item: WorkItem) -> Bool {
        guard usesDateRange else { return true }
        let from = calendar.startOfDay(for: min(rangeFrom, rangeTo))
        let lastDay = calendar.startOfDay(for: max(rangeFrom, rangeTo))
        let to = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let date = listDate(item)
        return date >= from && date < to
    }

    private func refresh() {
        guard hasLoaded else { return }
        let ranged = items.filter(inRange)
        counts = Dictionary(uniqueKeysWithValues: TaskHistoryFilter.allCases.map { filter in
            (filter, ranged.filter { matches($0, filter) }.count)
        })

        let shown = ranged
            .filter { matches($0, filter) }
            .sorted {
                let left = listDate($0)
                let right = listDate($1)
                if left != right { return left > right }
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.title < $1.title
            }
        let byDay = Dictionary(grouping: shown) { calendar.startOfDay(for: listDate($0)) }
        groups = byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: byDay[day] ?? [])
        }
    }
}

public struct TaskHistoryView: View {
    private let model: TaskHistoryViewModel
    @Environment(\.calendar) private var calendar

    public init(model: TaskHistoryViewModel) {
        self.model = model
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 480, minHeight: 380)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.load() }
        }
    }

    @MainActor
    private var header: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Task History", systemImage: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(model.resultCount) task\(model.resultCount == 1 ? "" : "s") · newest first")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            Picker("Show", selection: $model.filter) {
                ForEach(TaskHistoryFilter.allCases) { filter in
                    Text("\(filter.label)  \(model.counts[filter] ?? 0)").tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("history-filter")

            HStack(spacing: 8) {
                Toggle(isOn: $model.usesDateRange) {
                    Label("Date range", systemImage: "calendar")
                }
                .toggleStyle(.button)
                .help("Only show tasks dated between two days")
                .accessibilityIdentifier("history-range-toggle")

                if model.usesDateRange {
                    DatePicker("From", selection: $model.rangeFrom, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("From date")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    DatePicker("To", selection: $model.rangeTo, displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityLabel("To date")

                    Menu("Quick range") {
                        Button("Last 7 days") { setRange(daysBack: 6) }
                        Button("Last 30 days") { setRange(daysBack: 29) }
                        Button("Last 90 days") { setRange(daysBack: 89) }
                        Button("This month") { setThisMonth() }
                    }
                    .fixedSize()
                }

                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.15), value: model.usesDateRange)
        }
        .padding(16)
    }

    @MainActor
    private func setRange(daysBack: Int) {
        let today = calendar.startOfDay(for: .now)
        model.rangeFrom = calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
        model.rangeTo = today
    }

    @MainActor
    private func setThisMonth() {
        guard let month = calendar.dateInterval(of: .month, for: .now) else { return }
        model.rangeFrom = month.start
        model.rangeTo = month.end.addingTimeInterval(-1)
    }

    @MainActor
    @ViewBuilder
    private var content: some View {
        if model.isLoading && !model.hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.groups.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No tasks match")
                    .font(.body.weight(.medium))
                Text(model.usesDateRange
                    ? "Try a wider date range or another filter."
                    : "Try another filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                row(item)
                            }
                        } header: {
                            dayHeader(group)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    @MainActor
    private func dayHeader(_ group: TaskHistoryViewModel.DayGroup) -> some View {
        HStack(spacing: 6) {
            Text(dayTitle(group.day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
            Text(group.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            Spacer()
            Text("\(group.items.count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Palette.background)
    }

    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.relative(presentation: .named, unitsStyle: .wide)).capitalized
    }

    @MainActor
    private func row(_ item: WorkItem) -> some View {
        let done = item.status.isComplete
        let cancelled = item.status == .cancelled
        let overdue = model.isOverdue(item)

        return Button {
            model.onOpenDetail?(item.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done
                    ? "checkmark.circle.fill"
                    : (cancelled ? "xmark.circle" : (overdue ? "exclamationmark.circle.fill" : "circle")))
                    .foregroundStyle(done
                        ? DesignTokens.Palette.success
                        : (overdue ? DesignTokens.Palette.danger : DesignTokens.Palette.textSecondary))

                Text(item.title)
                    .strikethrough(done || cancelled)
                    .foregroundStyle(done || cancelled
                        ? DesignTokens.Palette.textSecondary
                        : DesignTokens.Palette.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(done ? "Completed" : (cancelled ? "Cancelled" : (overdue ? "Overdue" : "Open")))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            (done
                                ? DesignTokens.Palette.success
                                : (overdue ? DesignTokens.Palette.danger : DesignTokens.Palette.accent))
                                .opacity(cancelled ? 0 : 0.14)
                        )
                    )
                    .foregroundStyle(done
                        ? DesignTokens.Palette.success
                        : (cancelled
                            ? DesignTokens.Palette.textSecondary
                            : (overdue ? DesignTokens.Palette.danger : DesignTokens.Palette.accent)))

                Text(item.priority.label)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .frame(width: 64, alignment: .leading)

                Text(model.listDate(item), format: .dateTime.hour().minute())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .frame(width: 62, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            (done ? "Completed " : "Due ")
                + model.listDate(item).formatted(date: .abbreviated, time: .shortened)
                + " · click to open"
        )
    }
}
