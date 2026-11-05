#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Owns the quick-add capture panel (driver.md FR-02/FR-05).
///
/// One reusable floating panel: every presentation builds a fresh
/// `CaptureViewModel` (an empty draft) and replaces the hosted view, so the
/// title field focuses itself again and no stale draft survives. Saving or
/// cancelling closes the panel; the Today list updates through its live query.
@MainActor
public final class CaptureWindowController {
    private let environment: AppEnvironment
    private var panel: PanelWindow?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// True while the capture panel is on screen.
    public var isPresenting: Bool {
        panel?.isVisible ?? false
    }

    /// Opens an empty capture panel and focuses the title field.
    public func present() {
        let model = makeModel()
        model.prepare(dropped: [], recognized: [])

        let host = NSHostingView(rootView: CaptureSheetHost(model: model))
        let panel = panel ?? makePanel()
        panel.contentView = host
        panel.setContentSize(DesignTokens.Window.capture)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hides the panel, keeping it for the next presentation.
    public func dismiss() {
        panel?.orderOut(nil)
    }

    // MARK: - Construction

    private func makeModel() -> CaptureViewModel {
        CaptureViewModel(
            repository: environment.workItems,
            attachmentRepository: environment.attachments,
            materializer: environment.materializer,
            calendar: environment.workCalendar,
            deviceId: "local",
            onSaved: { [weak self] _ in self?.dismiss() },
            onCancel: { [weak self] in self?.dismiss() }
        )
    }

    private func makePanel() -> PanelWindow {
        let rect = NSRect(origin: .zero, size: DesignTokens.Window.capture)
        let panel = PanelWindow(contentRect: rect, style: .capture)
        panel.contentMinSize = DesignTokens.Window.capture
        panel.contentMaxSize = DesignTokens.Window.capture
        panel.isReleasedWhenClosed = false
        return panel
    }
}
#endif
