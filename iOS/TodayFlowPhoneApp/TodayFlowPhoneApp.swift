import SwiftUI
import TodayFlowPhone

@main
struct TodayFlowPhoneApp: App {
    @State private var environment: PhoneEnvironment = {
        do {
            return try PhoneEnvironment.makeProduction()
        } catch {
            // The database failed to open; keep the app usable for this run.
            return PhoneEnvironment.makeInMemory()
        }
    }()

    var body: some Scene {
        WindowGroup {
            PhoneRootView(environment: environment)
        }
    }
}
