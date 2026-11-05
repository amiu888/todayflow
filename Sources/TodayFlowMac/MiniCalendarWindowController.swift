#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// A tiny floating day/week calendar that can be parked in any screen corner
/// and stays on every desktop.
@MainActor
public final class MiniCalendarWindowController: NSObject, NSWindowDelegate {
    private static let cornerKey = "todayflow.miniCorner"
    private static let modeKey = "todayflow.miniMode"

    private let environment: AppEnvironment
    private var window: PanelWindow?
    private var model: MiniCalendarViewModel?
    private var corner: ScreenCorner?

    public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?
    public var onOpenMain: (@MainActor () -> Void)?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.corner = UserDefaults.standard.string(forKey: Self.cornerKey)
            .flatMap(ScreenCorner.init(rawValue:))
        super.init()
    }

    public var isPresenting: Bool {
        window?.isVisible ?? false
    }

    public func toggle() {
        isPresenting ? dismiss() : present()
    }

    public func present(mode: MiniCalendarViewModel.Mode? = nil) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let savedMode = UserDefaults.standard.string(forKey: Self.modeKey)
            .flatMap(MiniCalendarViewModel.Mode.init(rawValue:))
        let model = MiniCalendarViewModel(
            repository: environment.workItems,
            calendar: environment.workCalendar.calendar,
            mode: mode ?? savedMode ?? .day
        )
        model.onOpenDetail = { [weak self] id in self?.onOpenDetail?(id) }
        model.onOpenMain = { [weak self] in
            self?.dismiss()
            self?.onOpenMain?()
        }
        model.onClose = { [weak self] in self?.dismiss() }
        self.model = model

        let size = NSSize(width: 320, height: 310)
        let window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: size),
            style: .slimBar
        )
        window.contentViewController = NSHostingController(
            rootView: MiniCalendarView(
                model: model,
                pinnedCorner: corner,
                onPin: { [weak self] corner in self?.pin(to: corner) }
            )
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(size)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = window

        if corner != nil {
            applyCorner()
        } else {
            window.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func dismiss() {
        window?.close()
        window = nil
        model = nil
    }

    public func pin(to corner: ScreenCorner?) {
        self.corner = corner
        UserDefaults.standard.set(corner?.rawValue, forKey: Self.cornerKey)
        applyCorner()
    }

    private func applyCorner() {
        guard let window, let corner, let screen = window.screen ?? NSScreen.main else {
            return
        }
        let size = window.frame.size
        let origin = corner.origin(in: screen.visibleFrame, size: size)
        window.setFrame(
            NSRect(origin: origin, size: size),
            display: true,
            animate: true
        )
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
    }
}
#endif
