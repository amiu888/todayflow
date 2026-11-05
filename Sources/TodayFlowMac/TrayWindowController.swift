#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Tracks the main panel's origin and turns a panel move into a delta that
/// following tray windows apply. Split out so the geometry is unit-testable.
public struct TrayFollowTracker: Sendable {
    public private(set) var panelOrigin: CGPoint?

    public init() {}

    /// Returns the distance the panel moved since the last call, or nil on the
    /// first update / no movement.
    public mutating func updatePanelOrigin(_ origin: CGPoint) -> CGSize? {
        guard let previous = panelOrigin else {
            panelOrigin = origin
            return nil
        }
        panelOrigin = origin
        let delta = CGSize(
            width: origin.x - previous.x,
            height: origin.y - previous.y
        )
        return delta == .zero ? nil : delta
    }

    public static func isProgrammaticMove(
        actual: CGPoint,
        expected: CGPoint?,
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let expected else { return false }
        return abs(actual.x - expected.x) <= tolerance
            && abs(actual.y - expected.y) <= tolerance
    }
}

/// Hosts one window per open tray. Multiple tray windows can be open at once,
/// and each accepts tasks dragged from Today or another tray.
@MainActor
public final class TrayWindowController: NSObject, NSWindowDelegate {
    private let model: TodayViewModel
    private var windows: [UUIDv7: NSWindow] = [:]
    /// Tray windows that have not been moved by the user. They follow the panel
    /// while the panel is dragged or docked.
    private var followsPanel: Set<UUIDv7> = []
    private var expectedOrigins: [UUIDv7: CGPoint] = [:]
    private var follow = TrayFollowTracker()
    private weak var observedPanel: NSWindow?
    /// The main panel's frame; new tray windows attach to its right edge and
    /// then to the right edge of the last tray window.
    public var panelFrame: (@MainActor () -> NSRect?)?
    /// The live main panel; used to follow its movement.
    public var panelWindow: (@MainActor () -> NSWindow?)?

    public init(model: TodayViewModel) {
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    @objc private func panelDidMove(_ notification: Notification) {
        guard let panel = panelWindow?(),
              notification.object as? NSWindow === panel
        else { return }

        if observedPanel !== panel {
            observedPanel = panel
            follow = TrayFollowTracker()
            _ = follow.updatePanelOrigin(panel.frame.origin)
            return
        }

        updateFollowedTrays(panelOrigin: panel.frame.origin)
    }

    /// Applies a panel origin change to every tray that has not been moved by
    /// the user. Internal for deterministic tests; `panelDidMove` is the
    /// production caller.
    var followingCount: Int { followsPanel.count }

    func window(trayId: UUIDv7) -> NSWindow? { windows[trayId] }

    func updateFollowedTrays(panelOrigin: CGPoint) {
        guard let delta = follow.updatePanelOrigin(panelOrigin) else { return }
        for (id, window) in windows where followsPanel.contains(id) {
            var origin = window.frame.origin
            origin.x += delta.width
            origin.y += delta.height
            expectedOrigins[id] = origin
            // `display: false` keeps the content compositor out of the hot
            // path while the panel is dragged with several trays attached.
            window.setFrame(
                NSRect(origin: origin, size: window.frame.size),
                display: false,
                animate: false
            )
        }
    }

    public func open(trayId: UUIDv7) {
        if let window = windows[trayId] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let title = model.tray(id: trayId)?.name ?? "Tray"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tray · \(title)"
        window.contentViewController = NSHostingController(
            rootView: TrayDetailView(model: model, trayId: trayId)
        )
        // HostingController adopts the SwiftUI fitting size; pin the intended
        // tray size before placement so layout math and following are stable.
        window.setContentSize(NSSize(width: 420, height: 520))
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.animationBehavior = .none
        window.delegate = self
        // Attach to the right of the main panel, then to the right of the
        // last opened tray window. If the row is full, stack below it.
        if let visible = NSScreen.main?.visibleFrame {
            let frame = TrayWindowLayout.frame(
                size: window.frame.size,
                panel: panelFrame?(),
                existing: windows.values.map(\.frame),
                screen: visible
            )
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        windows[trayId] = window
        followsPanel.insert(trayId)
        expectedOrigins[trayId] = window.frame.origin
        if let panel = panelWindow?() {
            if observedPanel !== panel {
                observedPanel = panel
                follow = TrayFollowTracker()
            }
            _ = follow.updatePanelOrigin(panel.frame.origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func close(trayId: UUIDv7) {
        windows[trayId]?.close()
        windows[trayId] = nil
        followsPanel.remove(trayId)
        expectedOrigins[trayId] = nil
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let closed = windows.filter { $0.value === window }.map(\.key)
        windows = windows.filter { $0.value !== window }
        for id in closed {
            followsPanel.remove(id)
            expectedOrigins[id] = nil
        }
    }

    public func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key,
              followsPanel.contains(id)
        else { return }
        if TrayFollowTracker.isProgrammaticMove(
            actual: window.frame.origin,
            expected: expectedOrigins[id]
        ) {
            return
        }
        // The user moved this tray; detach it from the panel.
        followsPanel.remove(id)
        expectedOrigins[id] = nil
    }
}
#endif
