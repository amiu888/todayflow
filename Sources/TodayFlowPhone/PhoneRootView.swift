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
    @State private var calendarModel: CalendarViewModel
    @State private var search: QuickFindModel
    @State private var addDay: Date?
    @State private var sync: SyncController?
    private let notifications: PhoneNotificationController
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: PhoneEnvironment, notifications: PhoneNotificationController) {
        self.environment = environment
        self.notifications = notifications
        _today = State(initialValue: TodayViewModel(
            repository: environment.workItems,
            linkRepository: environment.links,
            attachmentRepository: environment.attachments,
            settingRepository: environment.settings,
            calendar: environment.workCalendar,
            deviceId: "local"
        ))
        _calendarModel = State(initialValue: CalendarViewModel(
            repository: environment.workItems,
            calendar: environment.workCalendar.calendar
        ))
        _search = State(initialValue: QuickFindModel(
            repository: environment.workItems,
            linkRepository: environment.links,
            attachmentRepository: environment.attachments,
            actionRepository: environment.actions,
            contactRepository: environment.contacts,
            calendar: environment.workCalendar
        ))
        _sync = State(initialValue: environment.databaseQueue.map {
            SyncController(
                queue: $0,
                databaseURL: environment.databaseURL,
                settings: environment.settings,
                keychain: environment.keychain
            )
        })
    }

    public var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Today", systemImage: "checklist", value: Tab.today) {
                NavigationStack(path: $todayPath) {
                    PhoneTodayView(
                        model: today,
                        environment: environment,
                        onAdd: {
                            addDay = today.activeDay
                            showingAdd = true
                        },
                        onSettings: { showingSettings = true }
                    )
                    .navigationDestination(for: UUIDv7.self) { id in
                        PhoneTaskDestination(id: id, environment: environment)
                    }
                }
            }
            SwiftUI.Tab("Calendar", systemImage: "calendar", value: Tab.calendar) {
                NavigationStack {
                    PhoneCalendarView(model: calendarModel) { day in
                        addDay = day
                        showingAdd = true
                    }
                    .navigationDestination(for: UUIDv7.self) { id in
                        PhoneTaskDestination(id: id, environment: environment)
                    }
                }
            }
            SwiftUI.Tab("Search", systemImage: "magnifyingglass", value: Tab.search, role: .search) {
                NavigationStack {
                    PhoneSearchView(model: search)
                        .navigationDestination(for: UUIDv7.self) { id in
                            PhoneTaskDestination(id: id, environment: environment)
                        }
                }
            }
        }
        .sheet(isPresented: $showingAdd, onDismiss: reloadAll) {
            PhoneQuickAddView(environment: environment, initialDay: addDay)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                PhoneSettingsView(environment: environment, sync: sync, notifications: notifications.settings)
            }
        }
        .task {
            await environment.loadSettings()
            await PhoneSampleData.seedIfRequested(environment)
            await sync?.start()
            await PhoneInboxImporter.importPending(environment)
            notifications.onOpen = { id in
                selection = .today
                todayPath = [id]
            }
            // The permission prompt waits for an answer; the list must not wait with it.
            Task {
                // Screenshots and recordings: `-noNotificationPrompt YES` skips the system prompt.
                // (Only a launch argument can set it; there is no setting for it.)
                if UserDefaults.standard.bool(forKey: "noNotificationPrompt") { return }
                await notifications.requestAuthorization()
                await notifications.refresh()
            }
            #if DEBUG
            // Screenshots and checks: `-openTask <uuid>` opens a task, `-tab calendar|search` picks a tab.
            let defaults = UserDefaults.standard
            if let raw = defaults.string(forKey: "openTask"), let uuid = UUID(uuidString: raw) {
                todayPath = [UUIDv7(uuid)]
            }
            switch defaults.string(forKey: "tab") {
            case "calendar": selection = .calendar
            case "search": selection = .search
            case "settings": showingSettings = true
            default: break
            }
            // End-to-end sync checks: `-pairServer <url> -pairCode <code>` pairs and turns sync on.
            if let server = defaults.string(forKey: "pairServer"), let code = defaults.string(forKey: "pairCode"),
               let sync, !sync.snapshot.isPaired {
                if let error = await sync.pair(server: server, code: code) {
                    print("TodayFlow debug pairing failed: \(error)")
                } else {
                    await sync.setEnabled(true)
                }
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
            // SyncController runs its own round when the app comes forward.
            if phase == .background { notifications.scheduleRefresh() }
            if phase == .active {
                Task {
                    await PhoneInboxImporter.importPending(environment)
                    reloadAll()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            reloadAll()
            notifications.scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.remindersChanged)) { _ in
            notifications.scheduleRefresh()
        }
        .onChange(of: selection) { reloadAll() }
    }

    private func reloadAll() {
        Task {
            await today.load()
            await calendarModel.load()
            await search.load()
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
            .onAppear { RecentTasks.record(id) }
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
