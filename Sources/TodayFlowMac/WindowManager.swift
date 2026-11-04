#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Owns the app's windows (driver.md lines 145-152). Windows are created on
/// demand, keyed by `WindowKind`, and reused while open. The panel and slim
/// bar are floating `PanelWindow`s; the rest are standard titled windows.
@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var windows: [WindowKind: NSWindow] = [:]

    /// The shared summary model (driver.md FR-40); the delegate assigns it
    /// after construction. The slim bar reads it in `body` so it stays live.
    public var summary: TodaySummaryModel?

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
        let window: NSWindow
        switch kind {
        case .panel, .slimBar:
            let style: PanelWindow.Style = kind == .panel ? .panel : .slimBar
            window = PanelWindow(contentRect: NSRect(origin: .zero, size: kind.size), style: style)
        default:
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: kind.size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        }
        window.title = kind.title
        if case .panel = kind {
            window.contentMinSize = DesignTokens.Window.panelMinimum
        }
        if case .slimBar = kind {
            window.contentMinSize = DesignTokens.Window.slimBar
            window.contentMaxSize = DesignTokens.Window.slimBar
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
                keychain: environment.keychain,
                calendar: environment.workCalendar.calendar
            )
        case .slimBar:
            if let summary {
                SlimBarView(
                    summary: summary,
                    onOpen: { [weak self] in self?.show(.panel) },
                    onDismiss: { [weak self] in self?.close(.slimBar) }
                )
            } else {
                EmptyView()
            }
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
