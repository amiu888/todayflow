import SwiftUI
import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// Day/week/month planning overview (FR-16 extended).
@MainActor
@Observable
public final class CalendarViewModel {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case week
        case month
        public var id: String { rawValue }
        public var label: String { self == .week ? "Week" : "Month" }
    }

    public struct Day: Identifiable, Hashable, Sendable {
        public let date: Date
        public let isToday: Bool
        public let isInCurrentMonth: Bool
        public let items: [WorkItem]
        public var id: Date { date }
        public var openCount: Int { items.filter { !$0.status.isTerminal }.count }
    }

    public var mode: Mode = .week
    public var anchor: Date
    public var selectedDay: Date
    public private(set) var items: [WorkItem] = []
    public private(set) var isLoading = false

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
        self.anchor = calendar.startOfDay(for: clock())
        self.selectedDay = calendar.startOfDay(for: clock())
        self.onOpenDetail = onOpenDetail
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await repository.allItems().filter { !$0.isDeleted }
    }

    public func show(_ mode: Mode) {
        self.mode = mode
    }

    public func previous() {
        shift(by: mode == .week ? -7 : -30)
    }

    public func next() {
        shift(by: mode == .week ? 7 : 30)
    }

    public func goToToday() {
        anchor = calendar.startOfDay(for: clock())
        selectedDay = anchor
    }

    /// Drag a task onto a day to move its start (and therefore its due date).
    public func reschedule(_ itemId: UUIDv7, to day: Date) async {
        let start = calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
        do {
            try await SetStartTime(
                repository: repository,
                calendar: WorkCalendar(calendar: calendar)
            ).execute(itemId, to: start, at: clock())
            await load()
        } catch {
            // The calendar is a view; the detail/Today surfaces show errors.
        }
    }

    public var title: String {
        switch mode {
        case .week:
            guard let end = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                return anchor.formatted(date: .abbreviated, time: .omitted)
            }
            return "\(weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        }
    }

    public var weekDays: [Day] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart)
            else { return nil }
            return day(for: date, inMonth: true)
        }
    }

    public var monthWeeks: [[Day]] {
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: anchor)
        ), let gridStart = calendar.date(
            byAdding: .day,
            value: -((calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7),
            to: monthStart
        ) else { return [] }

        return (0..<6).map { week in
            (0..<7).compactMap { day in
                guard let date = calendar.date(
                    byAdding: .day,
                    value: week * 7 + day,
                    to: gridStart
                ) else { return nil }
                return self.day(
                    for: date,
                    inMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
                )
            }
        }
    }

    public var selectedDayPlan: Day {
        day(for: selectedDay, inMonth: true)
    }

    public func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDay)
    }

    private var weekStart: Date {
        let start = calendar.startOfDay(for: anchor)
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: start) ?? start
    }

    private func shift(by days: Int) {
        anchor = calendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
    }

    private func day(for date: Date, inMonth: Bool) -> Day {
        let dayItems = items
            .filter { calendar.isDate($0.endAt, inSameDayAs: date) }
            .sorted {
                if $0.endAt != $1.endAt { return $0.endAt < $1.endAt }
                return $0.priority < $1.priority
            }
        return Day(
            date: date,
            isToday: calendar.isDateInToday(date),
            isInCurrentMonth: inMonth,
            items: dayItems
        )
    }
}

public struct CalendarView: View {
    private let model: CalendarViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(model: CalendarViewModel) {
        self.model = model
    }

    @MainActor
    public init(
        repository: any WorkItemRepository,
        calendar: Calendar = .current,
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        model = CalendarViewModel(
            repository: repository,
            calendar: calendar,
            onOpenDetail: onOpenDetail
        )
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.mode == .week {
                weekBoard
            } else {
                monthBoard
            }
        }
        .frame(minWidth: 700, minHeight: 540)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
    }

    @MainActor
    private var header: some View {
        HStack(spacing: 10) {
            Text(model.title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)

            Spacer()

            Picker("View", selection: Binding(
                get: { model.mode },
                set: { model.show($0) }
            )) {
                ForEach(CalendarViewModel.Mode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .help("Switch between week and month planning")

            Button { model.previous() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .help("Previous \(model.mode.label.lowercased())")

            Button("Today") { model.goToToday() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Jump to today")

            Button { model.next() } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .help("Next \(model.mode.label.lowercased())")
        }
        .padding(16)
    }

    @MainActor
    private var weekBoard: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(model.weekDays) { day in
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundStyle(day.isToday ? DesignTokens.Palette.accent : DesignTokens.Palette.textPrimary)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(day.items) { item in
                                Button(item.title) {
                                    model.onOpenDetail?(item.id)
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .lineLimit(2)
                                .help(item.descriptionMd.isEmpty ? item.title : item.descriptionMd)
                            }
                            if day.items.isEmpty {
                                Text("—")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(day.isToday ? DesignTokens.Palette.accent.opacity(0.08) : DesignTokens.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
                )
                .dropDestination(for: WorkItemDragPayload.self) { payloads, _ in
                    guard let payload = payloads.first else { return false }
                    Task { await model.reschedule(payload.itemId, to: day.date) }
                    return true
                }
            }
        }
        .padding(12)
    }

    @MainActor
    private var monthBoard: some View {
        VStack(spacing: 10) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(model.monthWeeks.flatMap { $0 }) { day in
                    Button {
                        model.selectedDay = day.date
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(day.date.formatted(.dateTime.day()))
                                    .font(.system(.callout, design: .rounded).weight(.semibold))
                                Spacer()
                                if day.openCount > 0 {
                                    Text("\(day.openCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(DesignTokens.Palette.accent))
                                }
                            }
                            Spacer(minLength: 0)
                            if !day.items.isEmpty {
                                Text(day.items.prefix(2).map(\.title).joined(separator: " · "))
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(5)
                        .frame(height: 62, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    model.isSelected(day.date)
                                        ? DesignTokens.Palette.accent.opacity(0.14)
                                        : DesignTokens.Palette.surface
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    day.isToday
                                        ? DesignTokens.Palette.accent.opacity(0.6)
                                        : DesignTokens.Palette.hairline,
                                    lineWidth: 1
                                )
                        )
                        .opacity(day.isInCurrentMonth ? 1 : 0.42)
                    }
                    .buttonStyle(.plain)
                    .help("\(day.openCount) open tasks · drop a task to move it here")
                    .dropDestination(for: WorkItemDragPayload.self) { payloads, _ in
                        guard let payload = payloads.first else { return false }
                        Task { await model.reschedule(payload.itemId, to: day.date) }
                        return true
                    }
                }
            }
            .padding(.horizontal, 12)

            HStack {
                Text(model.selectedDayPlan.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(model.selectedDayPlan.items.count) tasks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(model.selectedDayPlan.items) { item in
                        Button(item.title) {
                            model.onOpenDetail?(item.id)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .lineLimit(2)
                        .help(item.descriptionMd.isEmpty ? item.title : item.descriptionMd)
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
    }

}
