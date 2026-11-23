#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures
import UniformTypeIdentifiers

/// Hosts the Daily Report window (File ▸ Daily Report…, ⇧⌘R).
@MainActor
public final class DailyReportController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private(set) var window: NSWindow?
    private var model: DailyReportModel?
    public var mainWindowProvider: (@MainActor () -> NSWindow?)?
    /// Opens the AI Writer for the report text.
    public var rewriteAction: AIRewriteAction?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public func present() {
        if let window, let model {
            Task { await model.load() }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = DailyReportModel(repository: environment.workItems, calendar: environment.workCalendar)
        model.onCopy = { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        model.onEmail = { subject, body in
            guard let service = NSSharingService(named: .composeEmail) else { return }
            service.subject = subject
            service.perform(withItems: [body])
        }
        model.onSave = { [weak self] name, text in self?.save(name: name, text: text) }
        self.model = model

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Daily Report"
        window.contentViewController = NSHostingController(
            rootView: DailyReportView(model: model).environment(\.aiRewrite, rewriteAction)
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        WindowSizeMemory.makeResizable(window, name: "dailyReport", minimum: NSSize(width: 460, height: 440))
        WindowPlacement.besideMainWindow(window, main: mainWindowProvider?())
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func save(name: String, text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [name.hasSuffix(".md") ? UTType(filenameExtension: "md") ?? .plainText : .plainText]
        panel.canCreateDirectories = true
        let write: (URL) -> Void = { url in
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        if let window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK, let url = panel.url { write(url) }
            }
        } else if panel.runModal() == .OK, let url = panel.url {
            write(url)
        }
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
    }
}
#endif
