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
    public var mainWindowProvider: (@MainActor () -> NSWindow?)?
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
        model.emailSummarizerProvider = { [weak self] in
            guard let self, let ai = self.environment.ai else { return nil }
            return await ai.emailSummarizer()
        }

        let host = NSHostingView(
            rootView: CaptureSheetHost(
                model: model,
                onDropProviders: { [weak self, weak model] providers in
                    guard let self, let model else { return false }
                    return self.handleSheetDrop(providers, into: model)
                },
                onPaste: { [weak self, weak model] isEditingText in
                    guard let self, let model else { return false }
                    return self.handleSheetPaste(into: model, isEditingText: isEditingText)
                },
                onAddLink: { [weak self, weak model] url in
                    guard let self, let model else { return }
                    self.add([DroppedObject(url: url, uti: .url)], to: model, origin: "link")
                }
            )
        )
        let panel = panel ?? makePanel()
        panel.contentView = host
        panel.setContentSize(DesignTokens.Window.capture)
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        WindowPlacement.besideMainWindow(panel, main: mainWindowProvider?())
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

    /// Objects dropped onto the open sheet are added to the draft as
    /// attachments; the title and anything typed so far are kept.
    private func handleSheetDrop(_ providers: [NSItemProvider], into model: CaptureViewModel) -> Bool {
        // Some apps withdraw the drag item after the callback returns, so
        // snapshot the drag pasteboard synchronously as a fallback.
        let pasteboardFallback = DroppedObjectLoader.objectsFromDragPasteboard()
        guard !providers.isEmpty || !pasteboardFallback.isEmpty else { return false }
        Task { @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            let loaded = await DroppedObjectLoader().load(from: providers)
            let objects = loaded.isEmpty ? pasteboardFallback : loaded
            guard !objects.isEmpty else {
                model.reportDropFailure()
                return
            }
            let recognized = objects.map { self.environment.pipeline.recognize($0) }
            model.addObjects(dropped: objects, recognized: recognized)
            Diagnostics.log("capture", "sheet drop added=\(objects.count) total=\(model.draft.objects.count)")

            let enriched = await Enricher(fetcher: URLSessionFetcher()).enrich(model.draft)
            guard self.currentModel === model, self.isPresenting else { return }
            model.applyEnrichment(enriched)
        }
        return true
    }

    /// ⌘V in the New Task window: a copied image, file, or link is added to
    /// the draft as an attachment; plain text still pastes into the field.
    private func handleSheetPaste(into model: CaptureViewModel, isEditingText: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        guard DroppedObjectLoader.pasteRoute(
            types: pasteboard.types ?? [],
            isEditingText: isEditingText
        ) == .attach else { return false }
        let objects = DroppedObjectLoader.objectsFromClipboard(pasteboard)
        guard !objects.isEmpty else { return false }
        add(objects, to: model, origin: "paste")
        return true
    }

    /// Adds objects to the open sheet and fetches their titles/previews.
    private func add(_ objects: [DroppedObject], to model: CaptureViewModel, origin: String) {
        let recognized = objects.map { environment.pipeline.recognize($0) }
        model.addObjects(dropped: objects, recognized: recognized)
        Diagnostics.log("capture", "sheet \(origin) added=\(objects.count) total=\(model.draft.objects.count)")
        Task { @MainActor [weak self, weak model] in
            guard let self, let model else { return }
            let enriched = await Enricher(fetcher: URLSessionFetcher()).enrich(model.draft)
            guard self.currentModel === model, self.isPresenting else { return }
            model.applyEnrichment(enriched)
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
            contactRepository: environment.contacts,
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
