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
    @State private var todayPath: [UUIDv7] = []
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
                NavigationStack(path: $todayPath) {
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
            PhoneQuickAddView(environment: environment, initialDay: today.activeDay)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { PhonePlaceholder(title: "Settings") }
        }
        .task {
            await environment.loadSettings()
            await PhoneSampleData.seedIfRequested(environment)
            #if DEBUG
            // Screenshots and checks: `-openTask <uuid>` opens a task, `-tab calendar|search` picks a tab.
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: "openTask"), let uuid = UUID(uuidString: raw) {
                todayPath = [UUIDv7(uuid)]
            }
            switch defaults.string(forKey: "tab") {
            case "calendar": selection = .calendar
            case "search": selection = .search
            default: break
            }
            #endif
            await today.observe()
        }
        .onOpenURL { url in
            if let id = PhoneLinks.taskId(from: url) {
                selection = .today
                todayPath = [id]
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await today.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            Task { await today.load() }
        }
    }
}

/// `todayflow://task/<uuid>` opens a task (notifications, share confirmations).
public enum PhoneLinks {
    public static let scheme = "todayflow"

    public static func url(for id: UUIDv7) -> URL {
        URL(string: "\(scheme)://task/\(id.uuid.uuidString)")!
    }

    public static func taskId(from url: URL) -> UUIDv7? {
        guard url.scheme == scheme, url.host() == "task",
              let uuid = UUID(uuidString: url.lastPathComponent)
        else { return nil }
        return UUIDv7(uuid)
    }
}

/// Where a tapped task goes.
struct PhoneTaskDestination: View {
    let id: UUIDv7
    let environment: PhoneEnvironment

    var body: some View {
        PhoneDetailView(id: id, environment: environment)
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
