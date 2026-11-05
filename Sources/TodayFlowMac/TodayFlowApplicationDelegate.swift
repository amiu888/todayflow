#if canImport(AppKit)
import AppKit
import Foundation
import UniformTypeIdentifiers
import TodayFlowFeatures

/// The app's `NSApplicationDelegate` (driver.md build order 6): opens the
/// production environment, installs the menu-bar status item, and shows the
/// main panel. The status item is the app's home (6.2), so closing every
/// window keeps the app alive — quit comes from the status-item menu.
@MainActor
public final class TodayFlowApplicationDelegate: NSObject, NSApplicationDelegate {
    public private(set) var environment: AppEnvironment?
    public private(set) var windows: WindowManager?
    public private(set) var statusItem: StatusItemController?
    public private(set) var summary: TodaySummaryModel?
    /// The system-wide capture hotkey (FR-05, default ⌃⌥Space).
    public private(set) var hotKey: GlobalHotKey?
    /// Nudges and task reminders (FR-42/FR-44).
    public private(set) var notifications: NotificationController?
    /// The automatic end-of-day review (FR-43).
    public private(set) var endOfDayReview: EndOfDayReviewController?
    private weak var dockingMenuItem: NSMenuItem?
    private weak var allDesktopsMenuItem: NSMenuItem?
    /// AI planning and Q&A windows (driver.md §8).
    public private(set) var dayPlan: DayPlanWindowController?
    public private(set) var askAI: AskWindowController?

    public override init() {}

    public func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppearance()
        do {
            let environment = try AppEnvironment.makeProduction()
            self.environment = environment
            let summary = TodaySummaryModel(
                repository: environment.workItems,
                calendar: environment.workCalendar
            )
            self.summary = summary
            let windowManager = WindowManager(environment: environment)
            windowManager.summary = summary
            self.windows = windowManager
            let review = EndOfDayReviewController(environment: environment)
            self.endOfDayReview = review
            let dayPlan = DayPlanWindowController(environment: environment)
            dayPlan.onOpenSettings = { [weak windowManager] in windowManager?.show(.settings) }
            self.dayPlan = dayPlan
            let askAI = AskWindowController(environment: environment)
            askAI.onOpenSettings = { [weak windowManager] in windowManager?.show(.settings) }
            self.askAI = askAI
            let controller = StatusItemController(
                environment: environment,
                windowManager: windowManager,
                summary: summary
            )
            controller.onEndOfDayReview = { [weak review] in review?.present() }
            controller.onPlanDay = { [weak dayPlan] in dayPlan?.present() }
            controller.onAskAI = { [weak askAI] in askAI?.present() }
            controller.onExportJSON = { [weak self] in self?.export(.json) }
            controller.onExportCSV = { [weak self] in self?.export(.csv) }
            controller.onExportExcel = { [weak self] in self?.export(.xlsx) }
            self.statusItem = controller
            installMainMenu()
            summary.onRefreshed = { [weak controller, weak self] progress in
                controller?.apply(progress: progress)
                Task { @MainActor in
                    await self?.notifications?.refresh()
                }
            }
            summary.onEndOfDay = { [weak review] in review?.present() }
            let hotKey = GlobalHotKey { [weak windowManager] in
                windowManager?.showCapture()
            }
            self.hotKey = hotKey
            if !hotKey.isRegistered {
                NSLog("TodayFlow: ⌃⌥Space is unavailable; use the menu-bar New Task item.")
            }
            Task {
                await environment.loadSettings()
                await environment.backupDatabaseIfNeeded()
                summary.updateCalendar(environment.workCalendar)

                let notifications = NotificationController(
                    repository: environment.workItems,
                    linkRepository: environment.links,
                    reminders: environment.reminders,
                    calendar: environment.workCalendar,
                    onOpen: { windowManager.show(.panel) }
                )
                self.notifications = notifications
                await notifications.requestAuthorization()

                await summary.refresh()
                windowManager.show(.panel)
                summary.startPolling()
            }
        } catch {
            NSLog("TodayFlow: could not open the database — \(error)")
            let alert = NSAlert()
            alert.messageText = "TodayFlow could not start"
            alert.informativeText = "The task database could not be opened: \(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    /// 6.2: the status item is the app's home — closing every window keeps
    /// the app alive; quit comes from the status-item menu.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// FR-01: files dropped on the Dock icon open the capture sheet. (The
    /// SwiftPM executable has no bundle yet, but this is the path a bundled
    /// build uses; it also handles Finder "Open With".)
    public func application(_ application: NSApplication, open urls: [URL]) {
        let objects = urls.map { DroppedObjectLoader.object(forFileURL: $0) }
        windows?.receiveDrop(objects)
    }

    /// Clicking the app in the Dock brings Today forward.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        windows?.show(.panel)
        return true
    }

    /// A proper macOS menu bar: standard Edit commands (so text fields work),
    /// File capture/export, and View navigation. The status item remains the
    /// home, but every command is also discoverable here.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            item("About TodayFlow", #selector(about), key: "")
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            item("Settings…", #selector(openSettingsMenu), key: ",")
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            item("Quit TodayFlow", #selector(quitApp), key: "q")
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(item("New Task…", #selector(newTaskMenu), key: "n"))
        fileMenu.addItem(
            item("Capture Clipboard", #selector(captureClipboardMenu), key: "V", modifiers: [.command, .shift])
        )
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("End-of-Day Review…", #selector(reviewMenu), key: ""))
        fileMenu.addItem(item("Plan My Day…", #selector(planMenu), key: ""))
        fileMenu.addItem(item("Ask About Tasks…", #selector(askMenu), key: ""))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Export JSON…", #selector(exportJSONMenu), key: ""))
        fileMenu.addItem(item("Export CSV…", #selector(exportCSVMenu), key: ""))
        fileMenu.addItem(item("Export Excel…", #selector(exportExcelMenu), key: ""))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Minimize", #selector(minimizeMenu), key: "m"))
        fileMenu.addItem(responderItem("Close Window", #selector(NSWindow.performClose(_:)), key: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(responderItem("Undo", Selector(("undo:")), key: "z"))
        editMenu.addItem(responderItem("Redo", Selector(("redo:")), key: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Cut", #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(responderItem("Copy", #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(responderItem("Paste", #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(responderItem("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "Appearance")
        appearanceMenu.addItem(item("Dark", #selector(appearanceDark), key: ""))
        appearanceMenu.addItem(item("Light", #selector(appearanceLight), key: ""))
        appearanceMenu.addItem(item("Follow System", #selector(appearanceSystem), key: ""))
        appearanceItem.submenu = appearanceMenu
        viewMenu.addItem(appearanceItem)
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Today", #selector(showTodayMenu), key: "1"))
        viewMenu.addItem(item("Mini Calendar", #selector(toggleMiniCalendarMenu), key: "7"))
        viewMenu.addItem(item("Calendar", #selector(showCalendarMenu), key: "5"))
        viewMenu.addItem(item("Insights", #selector(showInsightsMenu), key: "6"))
        viewMenu.addItem(item("Upcoming", #selector(showUpcomingMenu), key: "2"))
        viewMenu.addItem(item("Completed", #selector(showCompletedMenu), key: "3"))
        viewMenu.addItem(item("Hierarchy", #selector(showHierarchyMenu), key: "4"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Slim Bar", #selector(showSlimBarMenu), key: ""))
        viewMenu.addItem(.separator())
        let docking = item("Dock to Edges", #selector(toggleDocking), key: "")
        docking.state = windows?.docking.isEnabled == true ? .on : .off
        dockingMenuItem = docking
        viewMenu.addItem(docking)

        let desktops = item("Show Windows on All Desktops", #selector(toggleAllDesktops), key: "")
        desktops.state = windows?.showOnAllDesktops == true ? .on : .off
        allDesktopsMenuItem = desktops
        viewMenu.addItem(desktops)
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        NSApp.mainMenu = main
    }

    private func item(
        _ title: String,
        _ action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = self
        return menuItem
    }

    /// Standard Edit commands must travel the responder chain to the focused
    /// text field; a nil target is what makes ⌘C/⌘V/⌘A work.
    private func responderItem(
        _ title: String,
        _ action: Selector,
        key: String
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = [.command]
        menuItem.target = nil
        return menuItem
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openSettingsMenu() {
        windows?.show(.settings)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func newTaskMenu() {
        windows?.showCapture()
    }

    @objc private func captureClipboardMenu() {
        windows?.captureClipboard()
    }

    @objc private func minimizeMenu() {
        windows?.minimizePanel()
    }

    @objc private func reviewMenu() {
        endOfDayReview?.present()
    }

    @objc private func planMenu() {
        dayPlan?.present()
    }

    @objc private func askMenu() {
        askAI?.present()
    }

    @objc private func exportJSONMenu() {
        export(.json)
    }

    @objc private func exportCSVMenu() {
        export(.csv)
    }

    @objc private func exportExcelMenu() {
        export(.xlsx)
    }

    // MARK: - Appearance

    private static let appearanceKey = "todayflow.appearance"

    /// Cinematic dark is the default; light and system-follow are one menu
    /// item away and persist across launches.
    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: Self.appearanceKey) {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "system":
            NSApp.appearance = nil
        default:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @objc private func appearanceDark() {
        UserDefaults.standard.set("dark", forKey: Self.appearanceKey)
        applyAppearance()
    }

    @objc private func appearanceLight() {
        UserDefaults.standard.set("light", forKey: Self.appearanceKey)
        applyAppearance()
    }

    @objc private func appearanceSystem() {
        UserDefaults.standard.set("system", forKey: Self.appearanceKey)
        applyAppearance()
    }

    @objc private func showTodayMenu() {
        windows?.show(.panel)
    }

    @objc private func showCalendarMenu() {
        windows?.show(.calendar)
    }

    @objc private func toggleMiniCalendarMenu() {
        windows?.toggleMiniCalendar()
    }

    @objc private func showInsightsMenu() {
        windows?.show(.insights)
    }

    @objc private func showUpcomingMenu() {
        windows?.show(.upcoming)
    }

    @objc private func showCompletedMenu() {
        windows?.show(.completed)
    }

    @objc private func showHierarchyMenu() {
        windows?.show(.hierarchy)
    }

    @objc private func showSlimBarMenu() {
        windows?.show(.slimBar)
    }

    @objc private func toggleDocking() {
        guard let docking = windows?.docking else { return }
        docking.isEnabled.toggle()
        dockingMenuItem?.state = docking.isEnabled ? .on : .off
    }

    @objc private func toggleAllDesktops() {
        guard let windows else { return }
        windows.showOnAllDesktops.toggle()
        allDesktopsMenuItem?.state = windows.showOnAllDesktops ? .on : .off
    }

    /// NFR-09: export the whole task store as JSON or CSV.
    private func export(_ format: DataExport.Format) {
        guard let environment else { return }
        Task { @MainActor in
            let items = await environment.workItems.allItems()

            let panel = NSSavePanel()
            panel.nameFieldStringValue = "TodayFlow.\(format.fileExtension)"
            switch format {
            case .json:
                panel.allowedContentTypes = [.json]
            case .csv:
                panel.allowedContentTypes = [.commaSeparatedText]
            case .xlsx:
                panel.allowedContentTypes = [
                    UTType(filenameExtension: "xlsx")
                        ?? UTType(filenameExtension: "zip")
                        ?? .data
                ]
            }
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try DataExport().write(items: items, format: format, to: url)
            } catch {
                self.presentExportError(error)
            }
        }
    }

    private func presentExportError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t export"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Releases the Carbon hotkey before the process exits.
    public func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
    }
}
#endif
