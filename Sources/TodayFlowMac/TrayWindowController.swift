#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Hosts one window per open tray. Multiple tray windows can be open at once,
/// and each accepts tasks dragged from Today or another tray.
@MainActor
public final class TrayWindowController: NSObject, NSWindowDelegate {
    private let model: TodayViewModel
    private var windows: [UUIDv7: NSWindow] = [:]
    /// The main panel's frame; new tray windows attach to its right edge and
    /// then to the right edge of the last tray window.
    public var panelFrame: (@MainActor () -> NSRect?)?

    public init(model: TodayViewModel) {
        self.model = model
        super.init()
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
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
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

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func close(trayId: UUIDv7) {
        windows[trayId]?.close()
        windows[trayId] = nil
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}
#endif
