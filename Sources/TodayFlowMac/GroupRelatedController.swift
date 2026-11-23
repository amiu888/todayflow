#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Shows "Group related tasks" for one task, beside the window it came from.
@MainActor
public final class GroupRelatedController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var model: GroupRelatedModel?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public func present(for taskId: UUIDv7, near source: NSWindow?) {
        let model = GroupRelatedModel(
            targetId: taskId,
            repository: environment.workItems,
            attachmentRepository: environment.attachments,
            actionRepository: environment.actions,
            contactRepository: environment.contacts,
            calendar: environment.workCalendar
        )
        model.onCancel = { [weak self] in self?.close() }
        model.onDone = { [weak self] message in
            guard let self else { return }
            let frame = self.window?.frame ?? .zero
            self.close()
            SavedToast.show(centeredOn: frame, message: message, duration: 1.6)
        }
        self.model = model

        let window = self.window ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: GroupRelatedView(model: model))
        WindowSizeMemory.makeResizable(window, name: "groupRelated", minimum: NSSize(width: 480, height: 420))
        WindowPlacement.besideMainWindow(window, main: source)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await model.load() }
    }

    public func close() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        model = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Group Related Tasks"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
#endif
