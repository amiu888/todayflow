#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowAI
import TodayFlowFeatures

/// Hosts the optional first-run AI setup window. It is deliberately separate
/// from Settings so a fresh install can make one informed choice without
/// walking through the full settings form.
@MainActor
public final class AIOnboardingController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    /// The Today panel (or slim bar) the new window should open beside.
    public var mainWindowProvider: (@MainActor () -> NSWindow?)?
    private var model: AIOnboardingViewModel?
    /// Called after the setup window closes (the first-run host uses this to
    /// defer the notification-permission prompt until the AI choice is done).
    public var onClose: (@MainActor () -> Void)?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public var isPresenting: Bool {
        window?.isVisible ?? false
    }

    public func present(force: Bool = false) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        show()
    }

    public func dismiss() {
        model?.cancelDownload()
        window?.close()
        window = nil
        model = nil
    }

    public func windowWillClose(_ notification: Notification) {
        let closingModel = model
        let callback = onClose
        closingModel?.cancelDownload()
        model = nil
        window = nil
        onClose = nil
        // Persist the "seen" flag before moving on to the deferred
        // notification prompt. If the app quits immediately, the next launch
        // should not show the setup window again.
        Task {
            await closingModel?.markComplete()
            callback?()
        }
    }

    private func show() {
        let model = AIOnboardingViewModel(
            installer: OllamaModelManager(),
            settings: environment.settings,
            keychain: environment.keychain,
            appleAvailable: Self.appleIntelligenceAvailable,
            discovering: LocalAIDiscovery()
        )
        model.onFinish = { [weak self] in self?.dismiss() }
        model.onOpenOllama = { [weak self] in self?.openOllama() }
        model.onGetOllama = {
            NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
        }
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set up AI"
        window.contentViewController = NSHostingController(
            rootView: AIOnboardingView(model: model)
        )
        // The main Today panel is a floating panel; keep the setup window
        // above it so the choice is never partially hidden.
        window.level = .floating
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        WindowPlacement.besideMainWindow(window, main: mainWindowProvider?())
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func openOllama() {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.electron.ollama"
        ) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
            return
        }
        let fallback = URL(fileURLWithPath: "/Applications/Ollama.app")
        if FileManager.default.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.open(fallback)
        } else {
            NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
        }
    }

    private static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleEmailSummarizer.isAvailable {
            return true
        }
        #endif
        return false
    }
}
#endif
