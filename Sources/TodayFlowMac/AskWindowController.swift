#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowAI
import TodayFlowCore
import TodayFlowFeatures

/// Hosts the "Ask about my tasks" sheet (driver.md §8). Streaming is cancelled
/// when the window closes, so an in-flight request never outlives the UI.
@MainActor
public final class AskWindowController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var model: AskViewModel?

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
                  let assistant = await ai.assistant(for: AIFeatures.ask)
            else {
                self.presentUnavailableAlert()
                return
            }
            self.show(assistant: assistant)
        }
    }

    private func show(assistant: any AIAssistant) {
        let model = AskViewModel(
            repository: environment.workItems,
            calendar: environment.workCalendar,
            assistant: assistant,
            onFinished: { [weak self] in self?.dismiss() }
        )
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask about tasks"
        window.contentViewController = NSHostingController(
            rootView: AskView(
                model: model,
                sentPayload: { [weak self] in self?.payloadText() }
            )
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
        model?.cancel()
        window?.close()
        window = nil
        model = nil
    }

    public func windowWillClose(_ notification: Notification) {
        // Closing the window is already the finish signal; clearing the hook
        // prevents `cancel()` from calling back into `dismiss()`.
        model?.onFinished = nil
        model?.cancel()
        model = nil
        window = nil
    }

    private func payloadText() -> String? {
        guard let request = environment.ai?.lastRequest else { return nil }
        return "POST \(request.url.absoluteString)\nModel: \(request.model)\nFeature: \(request.feature)\n\n\(request.body)"
    }

    private func presentUnavailableAlert() {
        let alert = NSAlert()
        alert.messageText = "AI is not available"
        alert.informativeText = "Turn on AI and the “Ask questions” feature in Settings to use this."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            onOpenSettings?()
        }
    }
}
#endif
