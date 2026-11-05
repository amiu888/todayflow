import SwiftUI
import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// Which screen corner a floating mini calendar is parked in.
public enum ScreenCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }

    /// Bottom-left origin in AppKit’s screen coordinates.
    public func origin(
        in visibleFrame: CGRect,
        size: CGSize,
        margin: CGFloat = 16
    ) -> CGPoint {
        let x: CGFloat
        let y: CGFloat
        switch self {
        case .topLeft:
            x = visibleFrame.minX + margin
            y = visibleFrame.maxY - size.height - margin
        case .topRight:
            x = visibleFrame.maxX - size.width - margin
            y = visibleFrame.maxY - size.height - margin
        case .bottomLeft:
            x = visibleFrame.minX + margin
            y = visibleFrame.minY + margin
        case .bottomRight:
            x = visibleFrame.maxX - size.width - margin
            y = visibleFrame.minY + margin
        }
        return CGPoint(x: x, y: y)
    }
}

@MainActor
@Observable
public final class MiniCalendarViewModel {
    public enum Mode: String, CaseIterable, Identifiable, Sendable {
        case day
        case week
        public var id: String { rawValue }
        public var label: String { self == .day ? "Day" : "Week" }
    }

    public struct Day: Identifiable, Hashable, Sendable {
        public let date: Date
        public let items: [WorkItem]
        public var id: Date { date }
        public var openCount: Int { items.filter { !$0.status.isTerminal }.count }
    }

    public var mode: Mode
    public var anchor: Date
    public private(set) var items: [WorkItem] = []
    public private(set) var isLoading = false

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?
    @ObservationIgnored public var onOpenMain: (@MainActor () -> Void)?
    @ObservationIgnored public var onClose: (@MainActor () -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { .now },
        mode: Mode = .day
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
        self.mode = mode
        self.anchor = calendar.startOfDay(for: clock())
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        items = await repository.allItems().filter { !$0.isDeleted && $0.kind == .task }
    }

    public func show(_ mode: Mode) { self.mode = mode }

    public func previous() {
        shift(by: mode == .day ? -1 : -7)
    }

    public func next() {
        shift(by: mode == .day ? 1 : 7)
    }

    public func goToToday() {
        anchor = calendar.startOfDay(for: clock())
    }

    public var title: String {
        switch mode {
        case .day:
            return anchor.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            let start = weekStart
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    public var dayItems: [WorkItem] {
        itemsForDay(anchor)
    }

    public var week: [Day] {
        (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart)
            else { return nil }
            return Day(date: date, items: itemsForDay(date))
        }
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

    private func itemsForDay(_ date: Date) -> [WorkItem] {
        items
            .filter { calendar.isDate($0.endAt, inSameDayAs: date) }
            .sorted {
                if $0.endAt != $1.endAt { return $0.endAt < $1.endAt }
                return $0.priority < $1.priority
            }
    }
}

/// A small floating day/week calendar. It is designed to live in a screen
/// corner on every desktop.
public struct MiniCalendarView: View {
    private let model: MiniCalendarViewModel
    private let pinnedCorner: ScreenCorner?
    private let onPin: (@MainActor (ScreenCorner?) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        model: MiniCalendarViewModel,
        pinnedCorner: ScreenCorner? = nil,
        onPin: (@MainActor (ScreenCorner?) -> Void)? = nil
    ) {
        self.model = model
        self.pinnedCorner = pinnedCorner
        self.onPin = onPin
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            if model.mode == .day {
                MiniDayList(
                    items: model.dayItems,
                    colorScheme: colorScheme,
                    onOpen: { model.onOpenDetail?($0) }
                )
            } else {
                weekList
            }
            footer
        }
        .padding(10)
        .frame(width: 320, height: 310)
        .background(DesignTokens.Palette.background)
        .background(alignment: .top) {
            DesignTokens.Palette.aurora.frame(height: 140)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
        .overlay(alignment: .top) { WindowDragGrabber() }
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
    }

    @MainActor
    private var header: some View {
        HStack(spacing: 5) {
            Button { model.previous() } label: {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .help("Previous")

            Text(model.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(DesignTokens.Palette.textPrimary)

            Button { model.next() } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .help("Next")

            Spacer()

            Picker("Mode", selection: Binding(
                get: { model.mode },
                set: { model.show($0) }
            )) {
                Text("Day").tag(MiniCalendarViewModel.Mode.day)
                Text("Week").tag(MiniCalendarViewModel.Mode.week)
            }
            .pickerStyle(.segmented)
            .frame(width: 92)
            .help("Switch between day and week")

            if let onPin {
                Menu {
                    Button("Unpin") { onPin(nil) }
                    Divider()
                    ForEach(ScreenCorner.allCases) { corner in
                        Button(corner.label) { onPin(corner) }
                    }
                } label: {
                    Image(systemName: pinnedCorner == nil ? "pin" : "pin.fill")
                        .font(.caption)
                        .foregroundStyle(
                            pinnedCorner == nil
                                ? DesignTokens.Palette.textSecondary
                                : DesignTokens.Palette.accent
                        )
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(pinnedCorner.map { "Pinned \($0.label.lowercased())" } ?? "Pin to a corner")
            }

            Button { model.onClose?() } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Close mini calendar")
        }
    }

    @MainActor
    private var weekList: some View {
        VStack(spacing: 2) {
            ForEach(model.week) { day in
                Button {
                    model.anchor = day.date
                    model.show(.day)
                } label: {
                    HStack(spacing: 5) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                day.openCount > 0
                                    ? DesignTokens.Palette.accent
                                    : DesignTokens.Palette.textSecondary
                            )
                            .frame(width: 30, alignment: .leading)
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.caption2.weight(.bold))
                            .frame(width: 20, alignment: .leading)

                        if let first = day.items.first {
                            Text(first.title)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        Spacer()
                        if day.openCount > 0 {
                            Text("\(day.openCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(DesignTokens.Palette.accent)
                                )
                        }
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(day.openCount) open tasks")
            }
        }
    }

    @MainActor
    private var footer: some View {
        HStack {
            Button { model.goToToday() } label: {
                Text("Today")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Palette.accent)
            .help("Jump to today")

            Spacer()

            Button {
                model.onOpenMain?()
            } label: {
                Label("Open Today", systemImage: "arrow.up.right.square")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Palette.accent)
            .help("Open the full Today panel")
        }
    }
}

private struct MiniDayList: View {
    let items: [WorkItem]
    let colorScheme: ColorScheme
    let onOpen: (UUIDv7) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                if items.isEmpty {
                    Text("Nothing due")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
                ForEach(items, id: \.id) { item in
                    Button {
                        onOpen(item.id)
                    } label: {
                        MiniDayRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .help(item.descriptionMd.isEmpty ? item.title : item.descriptionMd)
                }
            }
        }
    }
}

private struct MiniDayRow: View {
    let item: WorkItem

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            Text(item.title)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            Text(item.endAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(Color.secondary)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .contentShape(Rectangle())
    }
}
