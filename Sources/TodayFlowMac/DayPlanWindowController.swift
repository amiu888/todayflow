#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowAI
import TodayFlowCore
import TodayFlowFeatures

/// Hosts the "Plan my day" sheet (driver.md §8). The AI controls are hidden
/// when the feature is unavailable: the menu item shows a short explanation
/// instead of an empty window.
@MainActor
public final class DayPlanWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    /// The Today panel (or slim bar) the new window should open beside.
    public var mainWindowProvider: (@MainActor () -> NSWindow?)?

    /// Opens Settings from the "AI is off" alert.
    public var onOpenSettings: (() -> Void)?

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

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let ai = self.environment.ai,
                  let assistant = await ai.assistant(for: AIFeatures.planDay)
            else {
                self.presentUnavailableAlert()
                return
            }
            self.show(assistant: assistant)
        }
    }

    private func show(assistant: any AIAssistant) {
        let model = DayPlanViewModel(
            repository: environment.workItems,
            calendar: environment.workCalendar,
            assistant: assistant,
            onFinished: { [weak self] in self?.dismiss() }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Plan my day"
        window.contentViewController = NSHostingController(
            rootView: DayPlanView(
                model: model,
                sentPayload: { [weak self] in self?.payloadText() }
            )
        )
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        WindowPlacement.besideMainWindow(window, main: mainWindowProvider?())
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

    private func payloadText() -> String? {
        guard let request = environment.ai?.lastRequest else { return nil }
        return "POST \(request.url.absoluteString)\nModel: \(request.model)\nFeature: \(request.feature)\n\n\(request.body)"
    }

    private func presentUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "AI is not available"
        alert.informativeText = "Turn on AI and the “Plan my day” feature in Settings to use this."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onOpenSettings?()
        }
    }
}
#endif
