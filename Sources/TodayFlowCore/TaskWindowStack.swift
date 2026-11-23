import CoreGraphics
import Foundation

/// How open task windows are laid out.
public enum TaskWindowLayout: String, CaseIterable, Sendable, Hashable {
    /// Left where the user puts them.
    case free
    /// A pile beside the Today panel with every title bar showing.
    case stack
    /// Tiled side by side.
    case sideBySide
    /// One window with a tab per task.
    case tabs

    public var label: String {
        switch self {
        case .free: "Free"
        case .stack: "Stack"
        case .sideBySide: "Side by Side"
        case .tabs: "Tabs"
        }
    }

    public var symbol: String {
        switch self {
        case .free: "macwindow.on.rectangle"
        case .stack: "square.stack.3d.up"
        case .sideBySide: "rectangle.split.3x1"
        case .tabs: "menubar.dock.rectangle"
        }
    }
}

/// The order of task windows in the stack, tabs and switcher.
public enum TaskWindowOrder: String, CaseIterable, Sendable, Hashable {
    case priority, due, recent, manual

    public var label: String {
        switch self {
        case .priority: "Priority"
        case .due: "Due Date"
        case .recent: "Recently Opened"
        case .manual: "My Order"
        }
    }

    /// For narrow segmented controls.
    public var shortLabel: String {
        switch self {
        case .priority: "Priority"
        case .due: "Due"
        case .recent: "Recent"
        case .manual: "Mine"
        }
    }
}

/// One open task window, as the stack sees it.
public struct TaskWindowEntry: Hashable, Sendable, Identifiable {
    public var id: UUIDv7
    public var title: String
    public var priority: Priority
    public var dueAt: Date
    public var isDone: Bool
    public var openedAt: Date

    public init(id: UUIDv7, title: String, priority: Priority, dueAt: Date, isDone: Bool = false, openedAt: Date) {
        self.id = id
        self.title = title
        self.priority = priority
        self.dueAt = dueAt
        self.isDone = isDone
        self.openedAt = openedAt
    }

    public init(item: WorkItem, openedAt: Date) {
        self.init(
            id: item.id, title: item.title, priority: item.priority,
            dueAt: item.endAt, isDone: item.status.isTerminal, openedAt: openedAt
        )
    }
}

public enum TaskWindowStack {
    /// Entries in display order: the first is the front of the stack and the
    /// top of the switcher. `manual` lists ids in the user's own order.
    public static func sorted(_ entries: [TaskWindowEntry], by order: TaskWindowOrder, manual: [UUIDv7] = []) -> [TaskWindowEntry] {
        entries.sorted { a, b in
            switch order {
            case .priority:
                if a.priority != b.priority { return a.priority < b.priority }
                if a.dueAt != b.dueAt { return a.dueAt < b.dueAt }
            case .due:
                if a.dueAt != b.dueAt { return a.dueAt < b.dueAt }
                if a.priority != b.priority { return a.priority < b.priority }
            case .recent:
                if a.openedAt != b.openedAt { return a.openedAt > b.openedAt }
            case .manual:
                let ia = manual.firstIndex(of: a.id) ?? Int.max
                let ib = manual.firstIndex(of: b.id) ?? Int.max
                if ia != ib { return ia < ib }
                if a.openedAt != b.openedAt { return a.openedAt > b.openedAt }
            }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// The window title: priority, when it is due, then the task title, so
    /// a stacked window is recognisable from its title bar alone.
    ///
    ///     P1 · Due 3:00 PM — CHG0012345 - remove Java
    public static func windowTitle(
        _ entry: TaskWindowEntry, now: Date = .now, calendar: Calendar = .current
    ) -> String {
        "\(dueLabel(entry, now: now, calendar: calendar)) — \(entry.title.isEmpty ? "Untitled task" : entry.title)"
    }

    /// "P1 · Due 3:00 PM", "P2 · Overdue", "P3 · Due Fri", "Done".
    public static func dueLabel(_ entry: TaskWindowEntry, now: Date = .now, calendar: Calendar = .current) -> String {
        if entry.isDone { return "Done" }
        let priority = entry.priority.shortLabel
        if entry.dueAt < now { return "\(priority) · Overdue" }
        let when: String
        if calendar.isDate(entry.dueAt, inSameDayAs: now) {
            when = entry.dueAt.formatted(date: .omitted, time: .shortened)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(entry.dueAt, inSameDayAs: tomorrow) {
            when = "Tomorrow"
        } else if entry.dueAt.timeIntervalSince(now) < 6 * 86_400 {
            when = entry.dueAt.formatted(.dateTime.weekday(.abbreviated))
        } else {
            when = entry.dueAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(priority) · Due \(when)"
    }

    /// Frames for a pile of `count` windows (front first). The front window
    /// sits lowest; each one behind it is raised by `step` so its title bar
    /// shows above the windows in front. The pile fits in `area`.
    public static func stackFrames(
        count: Int, windowSize: CGSize, area: CGRect, step: CGFloat = 30, minimumHeight: CGFloat = 360
    ) -> [CGRect] {
        guard count > 0 else { return [] }
        let width = min(windowSize.width, area.width)
        var height = min(windowSize.height, area.height)
        var gap = step
        let needed = height + CGFloat(count - 1) * gap
        if needed > area.height {
            // Shrink the windows first, then tighten the title spacing.
            height = max(minimumHeight, area.height - CGFloat(count - 1) * gap)
            if height + CGFloat(count - 1) * gap > area.height, count > 1 {
                gap = max(18, (area.height - height) / CGFloat(count - 1))
            }
            height = min(height, area.height)
        }
        // The back window's top touches the top of the area.
        let top = area.maxY
        return (0..<count).map { index in
            // Window `index` (0 = front) is `count - 1 - index` steps below the back one.
            let windowTop = top - CGFloat(count - 1 - index) * gap
            let y = max(area.minY, windowTop - height)
            return CGRect(x: area.minX, y: y, width: width, height: height).integral
        }
    }

    /// Frames for `count` windows tiled in `area` (left to right, top to
    /// bottom), as many columns as fit at `minimumWidth`.
    public static func tileFrames(count: Int, area: CGRect, minimumWidth: CGFloat = 480, gap: CGFloat = 8) -> [CGRect] {
        guard count > 0 else { return [] }
        let maxColumns = max(1, Int((area.width + gap) / (minimumWidth + gap)))
        let columns = min(count, maxColumns)
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let width = (area.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let height = (area.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            return CGRect(
                x: area.minX + CGFloat(column) * (width + gap),
                y: area.maxY - CGFloat(row + 1) * height - CGFloat(row) * gap,
                width: width, height: height
            ).integral
        }
    }
}
