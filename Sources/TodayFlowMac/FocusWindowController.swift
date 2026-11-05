#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Hosts the focused-work timer window.
@MainActor
public final class FocusWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var model: FocusViewModel?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public var isPresenting: Bool {
        window?.isVisible ?? false
    }

    public func present(itemId: UUIDv7) {
        dismiss()

        let model = FocusViewModel(
            itemId: itemId,
            repository: environment.workItems,
            linkRepository: environment.links,
            onClosed: { [weak self] in self?.dismiss() }
        )
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus"
        window.contentViewController = NSHostingController(
            rootView: FocusView(model: model)
        )
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    public func dismiss() {
        model?.close()
        window?.close()
        window = nil
        model = nil
    }

    public func windowWillClose(_ notification: Notification) {
        model?.onClosed = nil
        model?.close()
        model = nil
        window = nil
    }
}
#endif
