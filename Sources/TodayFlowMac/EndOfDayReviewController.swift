#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowFeatures

/// Hosts the end-of-day review in its own window (driver.md FR-43).
///
/// Presented automatically once per day when end of business passes with open
/// tasks, and on demand from the menu-bar menu. Each presentation builds a
/// fresh view model so the list reflects the current repository state.
@MainActor
public final class EndOfDayReviewController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public var isPresenting: Bool {
        window?.isVisible ?? false
    }

    public func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = EndOfDayReviewViewModel(
            repository: environment.workItems,
            linkRepository: environment.links,
            calendar: environment.workCalendar,
            onFinished: { [weak self] in self?.dismiss() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "End of day"
        window.contentViewController = NSHostingController(
            rootView: EndOfDayReviewView(model: model)
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
        window?.close()
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
#endif
