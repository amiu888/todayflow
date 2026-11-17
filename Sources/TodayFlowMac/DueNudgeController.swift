#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Shows the on-screen due-soon popup when a task crosses into its 12-hour,
/// 5-hour or 1-hour window. `DueNudgePlanner` decides what fires; this class
/// owns the clock tick, the remembered stages, and the floating panel.
@MainActor
public final class DueNudgeController {
    /// UserDefaults flag behind View ▸ Due-Soon Popups. On unless turned off.
    public nonisolated static let enabledKey = "todayflow.dueNudgesEnabled"

    public static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private let repository: any WorkItemRepository
    private let settings: any SettingRepository
    private let clock: @Sendable () -> Date
    private let planner = DueNudgePlanner()
    private let onOpen: @MainActor (UUIDv7) -> Void

    private var memory: DueNudgePlanner.Memory = [:]
    private var memoryLoaded = false
    private var ticker: Task<Void, Never>?
    private var queue: [DueNudge] = []
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    public init(
        repository: any WorkItemRepository,
        settings: any SettingRepository,
        clock: @escaping @Sendable () -> Date = { .now },
        onOpen: @escaping @MainActor (UUIDv7) -> Void
    ) {
        self.repository = repository
        self.settings = settings
        self.clock = clock
        self.onOpen = onOpen
    }

    /// Checks now and then every half minute.
    public func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Plans against the current tasks and shows anything newly due soon.
    public func check() async {
        if !memoryLoaded {
            memoryLoaded = true
            if let raw = await settings.value(for: SettingKeys.dueNudgeMemory),
               let data = raw.data(using: .utf8),
               let stored = try? JSONDecoder().decode(DueNudgePlanner.Memory.self, from: data)
            {
                memory = stored
            }
        }

        let before = memory
        let items = await repository.allItems()
        let nudges = planner.plan(items: items, now: clock(), memory: &memory)
        if memory != before,
           let data = try? JSONEncoder().encode(memory),
           let raw = String(data: data, encoding: .utf8)
        {
            try? await settings.set(raw, for: SettingKeys.dueNudgeMemory)
        }

        guard Self.isEnabled, !nudges.isEmpty else { return }
        Diagnostics.log(
            "nudge",
            "due-soon " + nudges.map { "\($0.stage.rawValue)h “\($0.title)”" }.joined(separator: ", ")
        )
        enqueue(nudges)
    }

    /// Shows a sample popup (View ▸ Due-Soon Popups ▸ Preview).
    public func preview(_ stage: DueNudgeStage) {
        let due = clock().addingTimeInterval(stage.threshold - 120)
        queue.removeAll()
        hide(animated: false)
        enqueue([
            DueNudge(itemId: .new(), title: "Sample task: send the weekly report", dueAt: due, stage: stage),
        ], opensTask: false)
    }

    // MARK: Panel

    private var opensTask = true

    private func enqueue(_ nudges: [DueNudge], opensTask: Bool = true) {
        self.opensTask = opensTask
        // The most urgent goes first; a task already waiting is not repeated.
        for nudge in nudges where !queue.contains(where: { $0.itemId == nudge.itemId }) {
            queue.append(nudge)
        }
        queue.sort { $0.stage < $1.stage }
        if panel == nil { showNext() }
    }

    private func showNext() {
        guard !queue.isEmpty else { return }
        let nudge = queue.removeFirst()

        let size = DueNudgeView.panelSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: visible.maxX - size.width - 4,
            y: visible.maxY - size.height - 4
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let opensTask = self.opensTask
        panel.contentView = NSHostingView(
            rootView: DueNudgeView(
                nudge: nudge,
                onOpen: { [weak self] in
                    self?.hide(animated: true)
                    if opensTask { self?.onOpen(nudge.itemId) }
                },
                onDismiss: { [weak self] in self?.hide(animated: true) }
            )
        )
        panel.orderFrontRegardless()
        self.panel = panel

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(nudge.title) is due \(nudge.dueAt.formatted(date: .omitted, time: .shortened))",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )

        // The closer the deadline, the longer it stays.
        let seconds: Double
        switch nudge.stage {
        case .twelveHours: seconds = 8
        case .fiveHours: seconds = 12
        case .oneHour: seconds = 30
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    private func hide(animated: Bool) {
        dismissTask?.cancel()
        dismissTask = nil
        guard let panel else { return }
        self.panel = nil

        let finish: @MainActor () -> Void = { [weak self] in
            panel.orderOut(nil)
            guard let self, self.panel == nil else { return }
            self.showNext()
        }
        guard animated else {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { finish() }
        })
    }
}
#endif
