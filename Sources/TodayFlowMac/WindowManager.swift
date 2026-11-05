#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures
import TodayFlowRecognition

/// Owns the app's windows (driver.md lines 145-152). Windows are created on
/// demand, keyed by `WindowKind`, and reused while open. The panel and slim
/// bar are floating `PanelWindow`s; the rest are standard titled windows.
@MainActor
public final class WindowManager: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var windows: [WindowKind: NSWindow] = [:]
    private let capture: CaptureWindowController
    private let dropLoader = DroppedObjectLoader()

    /// The shared summary model (driver.md FR-40); the delegate assigns it
    /// after construction. The slim bar reads it in `body` so it stays live.
    public var summary: TodaySummaryModel?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.capture = CaptureWindowController(environment: environment)
        super.init()
    }

    /// Opens an empty quick-add capture panel (FR-05 hotkey).
    public func showCapture() {
        capture.present()
    }

    /// Opens the quick-add panel seeded with dropped objects (FR-01/FR-06).
    public func showCapture(dropped: [DroppedObject]) {
        guard !dropped.isEmpty else {
            showCapture()
            return
        }
        let recognized = dropped.map { environment.pipeline.recognize($0) }
        capture.present(dropped: dropped, recognized: recognized)
    }

    /// Converts an AppKit drop and routes it: onto a row, it becomes
    /// attachments on that task (FR-04); anywhere else it opens the sheet.
    /// Returns immediately so the drag operation completes without waiting for
    /// the provider loads.
    @discardableResult
    public func handleDrop(_ providers: [NSItemProvider], onto itemId: UUIDv7? = nil) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let objects = await self.dropLoader.load(from: providers)
            guard !objects.isEmpty else { return }
            if let itemId {
                await self.attach(objects, to: itemId)
            } else {
                self.showCapture(dropped: objects)
            }
        }
        return true
    }

    /// Handles objects that were already converted (menu-bar drags and
    /// `application(_:open:)` file drops).
    public func receiveDrop(_ objects: [DroppedObject]) {
        showCapture(dropped: objects)
    }

    /// Adds the dropped objects to an existing task (FR-04).
    private func attach(_ objects: [DroppedObject], to itemId: UUIDv7) async {
        guard await environment.workItems.item(itemId) != nil else { return }
        let recognized = objects.map { environment.pipeline.recognize($0) }
        let importer = TaskAttachmentImporter(
            attachmentRepository: environment.attachments,
            materializer: environment.materializer
        )
        do {
            try await importer.add(recognized, from: objects, to: itemId)
            NotificationCenter.default.post(name: TodayFlowEvents.attachmentsChanged, object: nil)
        } catch {
            presentAttachmentError(error)
        }
    }

    private func presentAttachmentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t add the attachment"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// True while the quick-add panel is on screen.
    public var isCapturePresenting: Bool {
        capture.isPresenting
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

    /// Assigns the optional breakdown assistant once Settings/Keychain resolve.
    private func attachAssistant(to model: DetailViewModel) {
        guard let ai = environment.ai else { return }
        Task { @MainActor in
            model.assistant = await ai.assistant(for: AIFeatures.breakDown)
        }
    }

    @ViewBuilder
    private func content(for kind: WindowKind) -> some View {
        switch kind {
        case .panel:
            TodayView(
                repository: environment.workItems,
                linkRepository: environment.links,
                attachmentRepository: environment.attachments,
                settingRepository: environment.settings,
                calendar: environment.workCalendar,
                onOpenTask: { [weak self] id in self?.show(.detail(id)) },
                onDrop: { [weak self] providers, itemId in
                    self?.handleDrop(providers, onto: itemId) ?? false
                }
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
                calendar: environment.workCalendar.calendar,
                modelCatalog: environment.ai
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
            let model = DetailViewModel(
                itemId: id,
                repository: environment.workItems,
                linkRepository: environment.links,
                attachmentRepository: environment.attachments,
                calendar: environment.workCalendar,
                onClosed: { [weak self] in self?.close(.detail(id)) }
            )
            let _ = attachAssistant(to: model)
            DetailView(model: model)
        }
    }
}
#endif
