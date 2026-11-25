import SwiftUI
import TodayFlowPhone

@main
struct TodayFlowPhoneApp: App {
    @State private var environment: PhoneEnvironment
    /// Created at launch so notification actions work even when iOS starts
    /// the app in the background to handle one.
    @State private var notifications: PhoneNotificationController

    init() {
        let environment: PhoneEnvironment
        do {
            environment = try PhoneEnvironment.makeProduction()
        } catch {
            // The database failed to open; keep the app usable for this run.
            environment = PhoneEnvironment.makeInMemory()
        }
        _environment = State(initialValue: environment)
        _notifications = State(initialValue: PhoneNotificationController(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView(environment: environment, notifications: notifications)
        }
    }
}
