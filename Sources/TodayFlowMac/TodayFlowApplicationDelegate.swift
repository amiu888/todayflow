#if canImport(AppKit)
import AppKit
import Foundation

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

    public override init() {}

    public func applicationDidFinishLaunching(_ notification: Notification) {
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
            let controller = StatusItemController(
                environment: environment,
                windowManager: windowManager,
                summary: summary
            )
            self.statusItem = controller
            summary.onRefreshed = { [weak controller, weak self] progress in
                controller?.apply(progress: progress)
                Task { @MainActor in
                    await self?.notifications?.refresh()
                }
            }
            let hotKey = GlobalHotKey { [weak windowManager] in
                windowManager?.showCapture()
            }
            self.hotKey = hotKey
            if !hotKey.isRegistered {
                NSLog("TodayFlow: ⌃⌥Space is unavailable; use the menu-bar New Task item.")
            }
            Task {
                await environment.loadSettings()
                summary.updateCalendar(environment.workCalendar)

                let notifications = NotificationController(
                    repository: environment.workItems,
                    linkRepository: environment.links,
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

    /// Releases the Carbon hotkey before the process exits.
    public func applicationWillTerminate(_ notification: Notification) {
        hotKey?.unregister()
    }
}
#endif
