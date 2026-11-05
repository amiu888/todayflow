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
    private let attachmentActions = AttachmentActions()
    private let focus: FocusWindowController
    private let miniCalendar: MiniCalendarWindowController
    /// Snaps floating windows to screen edges and neighbouring windows.
    public let docking = WindowDockController()
    /// When true, all app windows follow the user across every Space.
    public var showOnAllDesktops: Bool {
        didSet {
            UserDefaults.standard.set(showOnAllDesktops, forKey: Self.desktopsKey)
            for window in windows.values {
                applyDesktopBehavior(to: window)
            }
        }
    }

    private static let desktopsKey = "todayflow.allDesktops"

    /// The shared summary model (driver.md FR-40); the delegate assigns it
    /// after construction. The slim bar reads it in `body` so it stays live.
    public var summary: TodaySummaryModel?

    public init(environment: AppEnvironment) {
        self.environment = environment
        self.capture = CaptureWindowController(environment: environment)
        self.focus = FocusWindowController(environment: environment)
        self.miniCalendar = MiniCalendarWindowController(environment: environment)
        self.showOnAllDesktops = UserDefaults.standard.object(forKey: Self.desktopsKey) as? Bool ?? false
        super.init()
        self.miniCalendar.onOpenDetail = { [weak self] id in self?.show(.detail(id)) }
        self.miniCalendar.onOpenMain = { [weak self] in
            self?.show(.panel)
            self?.miniCalendar.dismiss()
        }
        self.capture.onSaved = { [weak self] id in
            guard let self else { return }
            NotificationCenter.default.post(name: TodayFlowEvents.itemsChanged, object: nil)
            self.show(.panel)

            Task { @MainActor [weak self] in
                guard let self else { return }
                let item = await self.environment.workItems.item(id)
                let message = self.captureConfirmation(for: item)
                // Let the Today view's notification subscription attach when
                // the panel was closed and has just been recreated.
                try? await Task.sleep(for: .milliseconds(150))
                NotificationCenter.default.post(
                    name: TodayFlowEvents.captureSaved,
                    object: nil,
                    userInfo: ["message": message]
                )
            }
        }
    }

    /// Opens an empty quick-add capture panel (FR-05 hotkey).
    public func showCapture() {
        capture.present()
    }

    /// Opens the quick-add panel seeded with dropped objects (FR-01/FR-06).
    /// `splitIntoTasks` is the ⌥-drop behavior: one task per object.
    public func showCapture(dropped: [DroppedObject], splitIntoTasks: Bool = false) {
        guard !dropped.isEmpty else {
            showCapture()
            return
        }
        let recognized = dropped.map { environment.pipeline.recognize($0) }
        capture.present(
            dropped: dropped,
            recognized: recognized,
            splitIntoTasks: splitIntoTasks
        )
    }

    /// Converts an AppKit drop and routes it: onto a row, it becomes
    /// attachments on that task (FR-04); anywhere else it opens the sheet.
    /// Returns immediately so the drag operation completes without waiting for
    /// the provider loads.
    @discardableResult
    public func handleDrop(_ providers: [NSItemProvider], onto itemId: UUIDv7? = nil) -> Bool {
        // The provider load is async and some apps withdraw their item after
        // the drop callback returns. Snapshot the drag pasteboard synchronously
        // first; it is the most reliable source for Finder file drags.
        let pasteboardFallback = DroppedObjectLoader.objectsFromDragPasteboard()
        DropDiagnostics.log(
            "drop providers=\(providers.count) "
                + "types=\(providers.map(\.registeredTypeIdentifiers)) "
                + "pasteboardFallback=\(pasteboardFallback.count)"
        )

        guard !providers.isEmpty || !pasteboardFallback.isEmpty else {
            DropDiagnostics.log("drop: no providers and no pasteboard objects")
            return false
        }

        // Read the modifier at drop time, before the async provider loads.
        let splitIntoTasks = NSEvent.modifierFlags.contains(.option)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await self.dropLoader.load(from: providers)
            let objects = loaded.isEmpty ? pasteboardFallback : loaded
            DropDiagnostics.log("drop: loaded=\(loaded.count) using=\(objects.count)")
            guard !objects.isEmpty else {
                self.presentDropError()
                return
            }
            if let itemId {
                DropDiagnostics.log("drop route=attach item=\(itemId) objects=\(objects.count)")
                await self.attach(objects, to: itemId)
            } else {
                DropDiagnostics.log("drop route=capture objects=\(objects.count)")
                self.showCapture(dropped: objects, splitIntoTasks: splitIntoTasks)
            }
        }
        return true
    }

    /// Handles objects that were already converted (menu-bar drags and
    /// `application(_:open:)` file drops).
    public func receiveDrop(_ objects: [DroppedObject], splitIntoTasks: Bool = false) {
        showCapture(dropped: objects, splitIntoTasks: splitIntoTasks)
    }

    /// Opens the focused-work timer for one task.
    public func presentFocus(_ id: UUIDv7) {
        focus.present(itemId: id)
    }

    /// Collapse the full panel into the corner-friendly mini calendar.
    public func collapseToMiniCalendar() {
        close(.panel)
        miniCalendar.present(mode: .day)
    }

    public func toggleMiniCalendar() {
        miniCalendar.toggle()
    }

    public func showMiniCalendar(mode: MiniCalendarViewModel.Mode) {
        miniCalendar.present(mode: mode)
    }

    public func pinMiniCalendar(to corner: ScreenCorner?) {
        if !miniCalendar.isPresenting {
            miniCalendar.present()
        }
        miniCalendar.pin(to: corner)
    }

    /// Minimize the Today panel; the menu-bar icon restores it.
    public func minimizePanel() {
        guard let panel = windows[.panel] ?? nil else {
            show(.panel)
            return
        }
        panel.miniaturize(nil)
    }

    /// File → Capture Clipboard: the same loader as a drop, from ⌘V content.
    public func captureClipboard() {
        let objects = DroppedObjectLoader.objects(from: .general)
        guard !objects.isEmpty else {
            presentDropError()
            return
        }
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

            // A drop on a row attaches to that task instead of creating one;
            // say so, otherwise it looks like nothing happened.
            let taskTitle = await environment.workItems.item(itemId)?.title ?? "task"
            let message: String
            if objects.count == 1 {
                message = "Attached “\(recognized[0].displayName)” to “\(taskTitle)”."
            } else {
                message = "Attached \(objects.count) items to “\(taskTitle)”."
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                NotificationCenter.default.post(
                    name: TodayFlowEvents.captureSaved,
                    object: nil,
                    userInfo: ["message": message]
                )
            }
        } catch {
            presentAttachmentError(error)
        }
    }

    /// A drop whose provider vended nothing (a source app can offer an
    /// unsupported private type) should say so instead of failing silently.
    private func presentDropError() {
        let alert = NSAlert()
        alert.messageText = "Couldn’t read that drop"
        alert.informativeText = "The app didn’t provide a file, link, image, or text this app can read. Try dragging it from Finder or copying and pasting it."
        alert.alertStyle = .informational
        alert.runModal()
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
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
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
        window.isMovableByWindowBackground = true
        if case .panel = kind {
            window.contentMinSize = DesignTokens.Window.panelMinimum
        }
        if case .slimBar = kind {
            window.contentMinSize = DesignTokens.Window.slimBar
            window.contentMaxSize = DesignTokens.Window.slimBar
        }
        window.contentView = NSHostingView(rootView: content(for: kind))
        window.isReleasedWhenClosed = false
        applyDesktopBehavior(to: window)
        return window
    }

    private func applyDesktopBehavior(to window: NSWindow) {
        if showOnAllDesktops {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        } else if !(window is PanelWindow) {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }

    /// A save confirmation that explains where the task actually landed.
    /// After business hours the capture's due date is the next working day,
    /// which is not on Today's list.
    private func captureConfirmation(for item: WorkItem?) -> String {
        guard let item else { return "Task saved." }
        let now = Date.now
        let eob = environment.workCalendar.endOfBusiness(for: now)
        let isToday = item.startAt <= eob
            && environment.workCalendar.calendar.isDate(item.startAt, inSameDayAs: now)

        if isToday {
            return "Added “\(item.title)” to Today."
        }
        let day = item.endAt.formatted(
            .dateTime.weekday(.wide).month(.abbreviated).day()
        )
        return "Added “\(item.title)” for \(day) — find it in Upcoming."
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
                onFocusTask: { [weak self] in self?.presentFocus($0) },
                onDrop: { [weak self] providers, itemId in
                    self?.handleDrop(providers, onto: itemId) ?? false
                },
                onOpenUpcoming: { [weak self] in self?.show(.upcoming) },
                onShowMiniCalendar: { [weak self] in self?.collapseToMiniCalendar() },
                windowActions: WindowMenuActions(
                    toggleDocking: { [weak self] in
                        self?.docking.isEnabled.toggle()
                    },
                    toggleAllDesktops: { [weak self] in
                        self?.showOnAllDesktops.toggle()
                    },
                    toggleMiniCalendar: { [weak self] in
                        self?.toggleMiniCalendar()
                    },
                    showMiniDay: { [weak self] in
                        self?.showMiniCalendar(mode: .day)
                    },
                    showMiniWeek: { [weak self] in
                        self?.showMiniCalendar(mode: .week)
                    },
                    pinMiniCalendar: { [weak self] corner in
                        self?.pinMiniCalendar(to: corner)
                    }
                )
            )
        case .hierarchy:
            HierarchyView(
                repository: environment.workItems,
                linkRepository: environment.links,
                calendar: environment.workCalendar,
                onOpenDetail: { [weak self] id in self?.show(.detail(id)) }
            )
        case .calendar:
            CalendarView(
                repository: environment.workItems,
                calendar: environment.workCalendar.calendar,
                onOpenDetail: { [weak self] id in self?.show(.detail(id)) }
            )
        case .insights:
            InsightsView(
                repository: environment.workItems,
                calendar: environment.workCalendar.calendar
            )
        case .upcoming:
            UpcomingView(
                repository: environment.workItems,
                calendar: environment.workCalendar,
                onOpenDetail: { [weak self] id in self?.show(.detail(id)) }
            )
        case .completed:
            CompletedHistoryView(
                repository: environment.workItems,
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
                activityRepository: environment.activities,
                reminderRepository: environment.reminders,
                calendar: environment.workCalendar,
                onClosed: { [weak self] in self?.close(.detail(id)) }
            )
            let _ = attachAssistant(to: model)
            let actions = attachmentActions
            DetailView(
                model: model,
                onOpenAttachment: { actions.open($0) },
                onOpenAttachmentWith: { actions.chooseApplication(for: $0) },
                defaultApplicationName: { actions.defaultApplicationName(for: $0) },
                onQuickLookAttachment: { actions.quickLook($0) },
                onRevealAttachment: { actions.reveal($0) },
                onDropAttachment: { [weak self] providers in
                    self?.handleDrop(providers, onto: id) ?? false
                }
            )
        }
    }
}
#endif
