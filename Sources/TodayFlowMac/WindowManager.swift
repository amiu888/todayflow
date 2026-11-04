#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Owns the app's titled windows (driver.md lines 145-152). Windows are created
/// on demand, keyed by `WindowKind`, and reused while open. 6.1 ships standard
/// windows; 6.2 turns the panel into a floating `NSPanel` with a status item.
@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var windows: [WindowKind: NSWindow] = [:]

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    /// Shows the window for `kind`, creating it on first use. Re-showing an
    /// open window just brings it to the front.
    public func show(_ kind: WindowKind) {
        if let window = windows[kind] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let window = makeWindow(for: kind)
        windows[kind] = window
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Closes the window for `kind`. The reference is dropped defensively as
    /// well as via `windowWillClose`, so it is deterministic even when the
    /// window was never ordered front.
    public func close(_ kind: WindowKind) {
        windows[kind]?.close()
        windows[kind] = nil
    }

    public func closeAll() {
        for window in Array(windows.values) {
            window.close()
        }
        windows.removeAll()
    }

    public func isOpen(_ kind: WindowKind) -> Bool {
        windows[kind] != nil
    }

    public var openCount: Int {
        windows.count
    }

    public func window(for kind: WindowKind) -> NSWindow? {
        windows[kind]
    }

    // MARK: NSWindowDelegate

    /// The dictionary is the window's owner (`isReleasedWhenClosed` is false),
    /// so this just drops the reference when the user closes the window.
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }

    // MARK: Window construction

    private func makeWindow(for kind: WindowKind) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: kind.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = kind.title
        if case .panel = kind {
            window.contentMinSize = DesignTokens.Window.panelMinimum
        }
        window.contentView = NSHostingView(rootView: content(for: kind))
        window.isReleasedWhenClosed = false
        return window
    }

    @ViewBuilder
    private func content(for kind: WindowKind) -> some View {
        switch kind {
        case .panel:
            TodayView(
                repository: environment.workItems,
                linkRepository: environment.links,
                attachmentRepository: environment.attachments,
                calendar: environment.workCalendar,
                onOpenTask: { [weak self] id in self?.show(.detail(id)) }
            )
        case .hierarchy:
            HierarchyView(
                repository: environment.workItems,
                linkRepository: environment.links,
                calendar: environment.workCalendar,
                onOpenDetail: { [weak self] id in self?.show(.detail(id)) }
            )
        case .settings:
            SettingsView(
                repository: environment.settings,
                calendar: environment.workCalendar.calendar
            )
        case .detail(let id):
            DetailView(
                model: DetailViewModel(
                    itemId: id,
                    repository: environment.workItems,
                    linkRepository: environment.links,
                    attachmentRepository: environment.attachments,
                    calendar: environment.workCalendar,
                    onClosed: { [weak self] in self?.close(.detail(id)) }
                )
            )
        }
    }
}
#endif
