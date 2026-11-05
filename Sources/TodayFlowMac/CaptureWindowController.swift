#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures
import TodayFlowRecognition

/// Owns the quick-add capture panel (driver.md FR-02/FR-05).
///
/// One reusable floating panel: every presentation builds a fresh
/// `CaptureViewModel` and replaces the hosted view, so the title field focuses
/// itself again and no stale draft survives. Saving or cancelling closes the
/// panel; the Today list updates through its live query.
@MainActor
public final class CaptureWindowController {
    private let environment: AppEnvironment
    private var panel: PanelWindow?
    private var currentModel: CaptureViewModel?
    /// Called after a successful save, after the sheet closes (the host uses
    /// it to force the Today list to refresh and come forward).
    public var onSaved: (@MainActor (UUIDv7) -> Void)?

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// True while the capture panel is on screen.
    public var isPresenting: Bool {
        panel?.isVisible ?? false
    }

    /// Opens the capture panel, optionally seeded with dropped objects.
    ///
    /// Recognition is synchronous and stays inside the 300 ms budget
    /// (NFR-01); enrichment (URL page titles) starts only after the panel is
    /// on screen, so a slow network never delays the sheet.
    public func present(
        dropped: [DroppedObject] = [],
        recognized: [RecognizedObject] = [],
        splitIntoTasks: Bool = false
    ) {
        let model = makeModel()
        model.prepare(
            dropped: dropped,
            recognized: recognized,
            splitIntoTasks: splitIntoTasks
        )
        currentModel = model

        let host = NSHostingView(rootView: CaptureSheetHost(model: model))
        let panel = panel ?? makePanel()
        panel.contentView = host
        panel.setContentSize(DesignTokens.Window.capture)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        Diagnostics.log(
            "capture",
            "panel visible=\(panel.isVisible) key=\(panel.isKeyWindow) "
                + "frame=\(NSStringFromRect(panel.frame)) objects=\(recognized.count)"
        )

        guard !recognized.isEmpty else { return }
        Task { @MainActor [weak self] in
            let enriched = await Enricher(fetcher: URLSessionFetcher()).enrich(model.draft)
            guard let self, self.currentModel === model, self.isPresenting else { return }
            model.applyEnrichment(enriched)

            // Smart title/summary is the last, optional enrichment step. It
            // runs after the panel is already usable, and a failure simply
            // leaves the recognized title in place (driver.md §8).
            guard let ai = self.environment.ai,
                  let assistant = await ai.assistant(for: AIFeatures.suggest)
            else { return }
            guard self.currentModel === model, self.isPresenting else { return }
            model.assistant = assistant
            await model.requestAISuggestion()
        }
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
            onSaved: { [weak self] id in
                self?.dismiss()
                self?.onSaved?(id)
            },
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
