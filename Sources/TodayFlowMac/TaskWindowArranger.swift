#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Keeps open task windows arranged (stack, side by side, tabs or free),
/// sorted, and titled with priority and due date; owns the switcher.
@MainActor
public final class TaskWindowArranger: NSObject {
    private static let layoutKey = "todayflow.taskWindows.layout"
    private static let orderKey = "todayflow.taskWindows.order"
    private static let manualKey = "todayflow.taskWindows.manual"
    private static let tabbingId = "TodayFlowTaskWindow"

    /// Open task windows by task id (from the window manager).
    var windowsProvider: (@MainActor () -> [UUIDv7: NSWindow])?
    /// The current task for an id (the window's model).
    var itemProvider: (@MainActor (UUIDv7) -> WorkItem?)?
    /// The Today panel (or slim bar) to arrange beside.
    var panelProvider: (@MainActor () -> NSWindow?)?
    var onClose: (@MainActor (UUIDv7) -> Void)?

    public let model = TaskWindowsModel()
    private var openedAt: [UUIDv7: Date] = [:]
    private var manual: [UUIDv7] = []
    private var switcher: NSPanel?
    private var keyObserver: NSObjectProtocol?

    public private(set) var layout: TaskWindowLayout
    public private(set) var order: TaskWindowOrder

    override public init() {
        let defaults = UserDefaults.standard
        layout = defaults.string(forKey: Self.layoutKey).flatMap(TaskWindowLayout.init) ?? .free
        order = defaults.string(forKey: Self.orderKey).flatMap(TaskWindowOrder.init) ?? .priority
        manual = (defaults.stringArray(forKey: Self.manualKey) ?? []).compactMap { UUID(uuidString: $0).map(UUIDv7.init) }
        super.init()
        model.layout = layout
        model.order = order
        model.onFocus = { [weak self] id in self?.focus(id) }
        model.onClose = { [weak self] id in self?.onClose?(id) }
        model.onCloseAll = { [weak self] in
            guard let self else { return }
            for id in self.windowsProvider?().keys.map({ $0 }) ?? [] { self.onClose?(id) }
        }
        model.onLayout = { [weak self] layout in self?.setLayout(layout) }
        model.onOrder = { [weak self] order in self?.setOrder(order) }
        model.onReorder = { [weak self] ids in self?.setManualOrder(ids) }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateActive() }
        }
    }

    // MARK: - Events from the window manager

    /// A task window opened: title it and fit it into the arrangement.
    func didOpen(_ id: UUIDv7, window: NSWindow) {
        openedAt[id] = openedAt[id] ?? .now
        window.tabbingIdentifier = Self.tabbingId
        window.tabbingMode = layout == .tabs ? .preferred : .disallowed
        refresh()
        if layout != .free {
            // After the window manager has placed and shown it.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.arrange(keepKey: id)
                }
            }
        }
    }

    /// A task window closed.
    func didClose(_ id: UUIDv7) {
        openedAt[id] = nil
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if self.layout == .stack || self.layout == .sideBySide { self.arrange(keepKey: nil) }
            }
        }
    }

    /// A task changed (title, priority, due): retitle; re-sort if needed.
    func didChange(_ id: UUIDv7) {
        let before = model.entries.map(\.id)
        refresh()
        if layout != .free, layout != .tabs, model.entries.map(\.id) != before {
            arrange(keepKey: NSApplication.shared.keyWindow.flatMap(taskId(of:)))
        }
    }

    // MARK: - Settings

    public func setLayout(_ layout: TaskWindowLayout) {
        let old = self.layout
        self.layout = layout
        model.layout = layout
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
        if old == .tabs, layout != .tabs { untab() }
        for window in sortedWindows() {
            window.tabbingMode = layout == .tabs ? .preferred : .disallowed
        }
        arrange(keepKey: NSApplication.shared.keyWindow.flatMap(taskId(of:)))
    }

    public func setOrder(_ order: TaskWindowOrder) {
        if order == .manual, manual.isEmpty { manual = model.entries.map(\.id) }
        self.order = order
        model.order = order
        UserDefaults.standard.set(order.rawValue, forKey: Self.orderKey)
        refresh()
        arrange(keepKey: NSApplication.shared.keyWindow.flatMap(taskId(of:)))
    }

    private func setManualOrder(_ ids: [UUIDv7]) {
        manual = ids
        UserDefaults.standard.set(ids.map(\.uuid.uuidString), forKey: Self.manualKey)
        if order != .manual {
            order = .manual
            model.order = .manual
            UserDefaults.standard.set(TaskWindowOrder.manual.rawValue, forKey: Self.orderKey)
        }
        refresh()
        arrange(keepKey: NSApplication.shared.keyWindow.flatMap(taskId(of:)))
    }

    // MARK: - Titles and order

    private func entries() -> [TaskWindowEntry] {
        let windows = windowsProvider?() ?? [:]
        let list = windows.keys.compactMap { id -> TaskWindowEntry? in
            guard let item = itemProvider?(id) else { return nil }
            return TaskWindowEntry(item: item, openedAt: openedAt[id] ?? .distantPast)
        }
        return TaskWindowStack.sorted(list, by: order, manual: manual)
    }

    /// Re-reads every open task, sets window titles, updates the switcher.
    func refresh() {
        let windows = windowsProvider?() ?? [:]
        let sorted = entries()
        for entry in sorted {
            guard let window = windows[entry.id] else { continue }
            let title = TaskWindowStack.windowTitle(entry)
            if window.title != title { window.title = title }
        }
        model.entries = sorted
        updateActive()
    }

    private func updateActive() {
        let id = NSApplication.shared.keyWindow.flatMap(taskId(of:))
        if model.activeId != id { model.activeId = id }
    }

    private func taskId(of window: NSWindow) -> UUIDv7? {
        // A tabbed window group reports the selected tab as key.
        windowsProvider?().first { $0.value === window }?.key
    }

    private func sortedWindows() -> [NSWindow] {
        let windows = windowsProvider?() ?? [:]
        return entries().compactMap { windows[$0.id] }
    }

    // MARK: - Arranging

    /// The part of the screen beside the Today panel.
    private func area(for screen: NSScreen?) -> CGRect {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        guard let panel = panelProvider?(), panel.isVisible, visible.intersects(panel.frame) else {
            return visible.insetBy(dx: 8, dy: 8)
        }
        let gap: CGFloat = 8
        let rightSpace = visible.maxX - panel.frame.maxX
        let leftSpace = panel.frame.minX - visible.minX
        if rightSpace >= leftSpace {
            return CGRect(x: panel.frame.maxX + gap, y: visible.minY + gap,
                          width: rightSpace - 2 * gap, height: visible.height - 2 * gap)
        }
        return CGRect(x: visible.minX + gap, y: visible.minY + gap,
                      width: leftSpace - 2 * gap, height: visible.height - 2 * gap)
    }

    /// Applies the current layout. `keepKey` stays the focused window.
    public func arrange(keepKey: UUIDv7?) {
        let windows = sortedWindows().filter { !$0.isMiniaturized }
        guard !windows.isEmpty else { return }
        let screen = panelProvider?()?.screen ?? windows.first?.screen
        let area = self.area(for: screen)

        switch layout {
        case .free:
            return
        case .stack:
            let saved = UserDefaults.standard.string(forKey: WindowSizeMemory.key("detail")).map(NSSizeFromString)
            let content = saved ?? DesignTokens.Window.detail
            let size = windows[0].frameRect(forContentRect: NSRect(origin: .zero, size: content)).size
            let frames = TaskWindowStack.stackFrames(
                count: windows.count, windowSize: size, area: area,
                step: titleBarHeight(windows[0]) + 2,
                minimumHeight: windows[0].frameRect(forContentRect: NSRect(origin: .zero, size: DesignTokens.Window.detailMinimum)).height
            )
            // Back to front, so each nearer window covers the one behind
            // except for its title bar.
            for (window, frame) in zip(windows, frames).reversed() {
                window.setFrame(frame, display: true, animate: false)
                window.orderFront(nil)
            }
            windows[0].makeKeyAndOrderFront(nil)
        case .sideBySide:
            let frames = TaskWindowStack.tileFrames(
                count: windows.count, area: area, minimumWidth: DesignTokens.Window.detailMinimum.width
            )
            for (window, frame) in zip(windows, frames) {
                window.setFrame(frame, display: true, animate: false)
                window.orderFront(nil)
            }
            focusWindow(keepKey, in: windows)
        case .tabs:
            let base = windows[0]
            var previous = base
            for window in windows.dropFirst() {
                if window.tabGroup !== base.tabGroup || base.tabGroup == nil {
                    previous.addTabbedWindow(window, ordered: .above)
                }
                previous = window
            }
            focusWindow(keepKey, in: windows)
        }
        updateActive()
    }

    private func focusWindow(_ id: UUIDv7?, in windows: [NSWindow]) {
        let all = windowsProvider?() ?? [:]
        (id.flatMap { all[$0] } ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    private func titleBarHeight(_ window: NSWindow) -> CGFloat {
        let height = window.frame.height - window.contentLayoutRect.height
        return height > 10 && height < 80 ? height : 28
    }

    private func untab() {
        for window in sortedWindows() where (window.tabbedWindows?.count ?? 0) > 1 {
            window.moveTabToNewWindow(nil)
        }
    }

    /// Brings a task window forward (switcher click). In the stack the
    /// window comes to the front where it is.
    public func focus(_ id: UUIDv7) {
        guard let window = windowsProvider?()[id] else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updateActive()
    }

    // MARK: - Switcher

    public func toggleSwitcher() {
        if let switcher, switcher.isVisible {
            switcher.orderOut(nil)
            return
        }
        let panel = switcher ?? makeSwitcher()
        switcher = panel
        refresh()
        if !panel.isVisible {
            let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
            panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 20, y: visible.maxY - panel.frame.height - 20))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeSwitcher() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 420),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Task Windows"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: TaskWindowsView(model: model))
        WindowSizeMemory.makeResizable(panel, name: "taskWindows", minimum: NSSize(width: 320, height: 280))
        panel.setFrameAutosaveName("TodayFlowTaskWindowsSwitcher")
        return panel
    }
}
#endif
