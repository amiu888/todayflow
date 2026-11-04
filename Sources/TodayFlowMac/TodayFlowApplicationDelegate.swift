#if canImport(AppKit)
import AppKit
import Foundation

/// The app's `NSApplicationDelegate` (driver.md build order 6): opens the
/// production environment, shows the main panel, and quits when the last
/// window closes. 6.2 flips the last part once the status item is the home.
@MainActor
public final class TodayFlowApplicationDelegate: NSObject, NSApplicationDelegate {
    public private(set) var environment: AppEnvironment?
    public private(set) var windows: WindowManager?

    public override init() {}

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let environment = try AppEnvironment.makeProduction()
            self.environment = environment
            let windowManager = WindowManager(environment: environment)
            self.windows = windowManager
            Task {
                await environment.loadSettings()
                windowManager.show(.panel)
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

    /// 6.1: closing the last window quits the app. 6.2 flips this to `false`
    /// once the menu-bar status item becomes the app's home.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
