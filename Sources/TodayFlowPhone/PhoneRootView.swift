#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The three tabs of the iPhone app (docs/ios/DESIGN.md §3).
public struct PhoneRootView: View {
    public enum Tab: Hashable { case today, calendar, search }

    private let environment: PhoneEnvironment
    @State private var selection: Tab = .today

    public init(environment: PhoneEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "checklist", value: Tab.today) {
                NavigationStack { PhonePlaceholder(title: "Today") }
            }
            SwiftUI.Tab("Calendar", systemImage: "calendar", value: Tab.calendar) {
                NavigationStack { PhonePlaceholder(title: "Calendar") }
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                NavigationStack { PhonePlaceholder(title: "Search") }
            }
        }
        .task { await environment.loadSettings() }
    }
}

/// Stand-in for a tab until its screen lands.
struct PhonePlaceholder: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Coming in the next build."))
            .navigationTitle(title)
    }
}
#endif
