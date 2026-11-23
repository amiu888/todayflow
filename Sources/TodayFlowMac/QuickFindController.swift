#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// The Quick Find panel: centered near the top of the screen like
/// Spotlight, closes when it loses focus or on esc.
@MainActor
public final class QuickFindController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var panel: PanelWindow?
    private var model: QuickFindModel?

    public var onOpenTask: (@MainActor (UUIDv7) -> Void)?
    public var onAsk: (@MainActor (String) -> Void)?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    public var isVisible: Bool { panel?.isVisible ?? false }

    public func toggle() {
        isVisible ? close() : present()
    }

    public func present() {
        let model = self.model ?? makeModel()
        model.text = ""
        model.selection = 0
        self.model = model

        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        position(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        Task { await model.load() }
    }

    public func close() {
        panel?.orderOut(nil)
    }

    public func windowDidResignKey(_ notification: Notification) {
        // Like Spotlight: clicking elsewhere puts it away.
        close()
    }

    private func makeModel() -> QuickFindModel {
        let model = QuickFindModel(
            repository: environment.workItems,
            linkRepository: environment.links,
            attachmentRepository: environment.attachments,
            actionRepository: environment.actions,
            contactRepository: environment.contacts,
            calendar: environment.workCalendar
        )
        model.onOpen = { [weak self] id in self?.onOpenTask?(id) }
        model.onClose = { [weak self] in self?.close() }
        if onAsk != nil {
            model.onAsk = { [weak self] question in self?.onAsk?(question) }
        }
        return model
    }

    private func makePanel(model: QuickFindModel) -> PanelWindow {
        let size = NSSize(width: 640, height: 460)
        let panel = PanelWindow(contentRect: NSRect(origin: .zero, size: size), style: .capture)
        panel.contentView = NSHostingView(rootView: QuickFindView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        WindowSizeMemory.makeResizable(panel, name: "quickFind", minimum: NSSize(width: 520, height: 360))
        return panel
    }

    /// Centered, a fifth of the way down the screen with the mouse.
    private func position(_ panel: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return panel.center() }
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - visible.height * 0.2 - size.height
        )
        panel.setFrameOrigin(NSPoint(x: origin.x.rounded(), y: max(visible.minY, origin.y).rounded()))
    }
}
#endif
