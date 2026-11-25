#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// The three tabs of the iPhone app (docs/ios/DESIGN.md §3).
public struct PhoneRootView: View {
    public enum Tab: Hashable { case today, calendar, search }

    private let environment: PhoneEnvironment
    @State private var selection: Tab = .today
    @State private var today: TodayViewModel
    @State private var showingAdd = false
    @State private var showingSettings = false
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: PhoneEnvironment) {
        self.environment = environment
        _today = State(initialValue: TodayViewModel(
            repository: environment.workItems,
            linkRepository: environment.links,
            attachmentRepository: environment.attachments,
            settingRepository: environment.settings,
            calendar: environment.workCalendar,
            deviceId: "local"
        ))
    }

    public var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "checklist", value: Tab.today) {
                NavigationStack {
                    PhoneTodayView(
                        model: today,
                        environment: environment,
                        onAdd: { showingAdd = true },
                        onSettings: { showingSettings = true }
                    )
                    .navigationDestination(for: UUIDv7.self) { id in
                        PhoneTaskDestination(id: id, environment: environment)
                    }
                }
            }
            SwiftUI.Tab("Calendar", systemImage: "calendar", value: Tab.calendar) {
                NavigationStack { PhonePlaceholder(title: "Calendar") }
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                NavigationStack { PhonePlaceholder(title: "Search") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            PhonePlaceholder(title: "New Task")
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { PhonePlaceholder(title: "Settings") }
        }
        .task {
            await environment.loadSettings()
            await PhoneSampleData.seedIfRequested(environment)
            await today.observe()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await today.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            Task { await today.load() }
        }
    }
}

/// Where a tapped task goes; the detail screen replaces it in M4.
struct PhoneTaskDestination: View {
    let id: UUIDv7
    let environment: PhoneEnvironment

    var body: some View {
        PhonePlaceholder(title: "Task")
    }
}

/// Stand-in for a screen until it lands.
struct PhonePlaceholder: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Coming in the next build."))
            .navigationTitle(title)
    }
}
#endif
