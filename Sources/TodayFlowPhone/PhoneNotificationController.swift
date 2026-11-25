#if os(iOS)
import Foundation
import TodayFlowCore
import TodayFlowFeatures
import UserNotifications

/// Local notifications on the iPhone (docs/ios/DESIGN.md §6): per-task
/// reminders and due-soon nudges 12 h, 5 h and 1 h before a task is due,
/// with Complete / Tomorrow / Open actions.
///
/// Everything is rebuilt by `refresh()` from the database, so a change made
/// on the Mac and synced here moves the phone's notifications too.
@MainActor
public final class PhoneNotificationController: NSObject, UNUserNotificationCenterDelegate {
    enum Action {
        static let complete = "TODAYFLOW_COMPLETE"
        static let tomorrow = "TODAYFLOW_TOMORROW"
        static let open = "TODAYFLOW_OPEN"
    }

    static let categoryID = "TODAYFLOW_TASK"
    nonisolated static let itemIdKey = "itemId"
    static let prefixes = ["reminder.", "nudge."]
    /// iOS keeps at most 64 pending notifications per app.
    static let limit = 60
    /// Nudges are planned for tasks due within this window.
    static let horizon: TimeInterval = 8 * 24 * 3600

    public let settings: PhoneNotificationSettings
    /// Opens a task (notification tap or the Open action). A tap that
    /// arrives before the screen exists waits in `pendingOpen`.
    public var onOpen: (@MainActor (UUIDv7) -> Void)? {
        didSet {
            if let onOpen, let id = pendingOpen {
                pendingOpen = nil
                onOpen(id)
            }
        }
    }
    public private(set) var pendingOpen: UUIDv7?

    private let environment: PhoneEnvironment
    private let center: UNUserNotificationCenter
    private var refreshTask: Task<Void, Never>?

    public init(environment: PhoneEnvironment, center: UNUserNotificationCenter = .current()) {
        self.environment = environment
        self.center = center
        self.settings = PhoneNotificationSettings()
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryID,
                actions: [
                    UNNotificationAction(identifier: Action.complete, title: "Complete", icon: .init(systemImageName: "checkmark")),
                    UNNotificationAction(identifier: Action.tomorrow, title: "Tomorrow", icon: .init(systemImageName: "arrow.right")),
                    UNNotificationAction(identifier: Action.open, title: "Open", options: .foreground),
                ],
                intentIdentifiers: []
            ),
        ])
        settings.onChange = { [weak self] in self?.scheduleRefresh() }
    }

    /// Asks once; later calls return the stored answer.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Coalesces bursts of changes (sync rounds, edits) into one rebuild.
    public func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    public func refresh(now: Date = .now) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }
        let requests = await plannedRequests(now: now)
        let pending = await center.pendingNotificationRequests().map(\.identifier)
            .filter { id in Self.prefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for request in requests {
            try? await center.add(request)
        }
    }

    /// The notifications that should be pending now, soonest first, capped at `limit`.
    func plannedRequests(now: Date) async -> [UNNotificationRequest] {
        var planned: [(Date, UNNotificationRequest)] = []
        var hasReminder = Set<UUIDv7>()

        if settings.remindersOn {
            for reminder in await environment.reminders.pending(after: now) where reminder.kind == .task {
                guard let id = reminder.itemId, let item = await environment.workItems.item(id),
                      !item.isDeleted, !item.status.isTerminal
                else { continue }
                hasReminder.insert(id)
                let body = "Reminder · due \(item.endAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
                planned.append((reminder.fireAt, request(
                    id: "reminder.\(reminder.id)", item: item, body: body, at: reminder.fireAt, now: now
                )))
            }
        }

        if settings.nudgesOn {
            let open = await environment.workItems.allItems().filter {
                $0.kind == .task && !$0.isDeleted && !$0.status.isTerminal
                    && $0.endAt > now && $0.endAt.timeIntervalSince(now) < Self.horizon
            }
            for item in open {
                for stage in DueNudgeStage.allCases {
                    let fireAt = item.endAt.addingTimeInterval(-stage.threshold)
                    guard fireAt > now else { continue }
                    // A task with its own reminder skips the 1-hour nudge.
                    if stage == .oneHour, hasReminder.contains(item.id) { continue }
                    let body = "Due in \(stage.rawValue) hour\(stage.rawValue == 1 ? "" : "s") · "
                        + item.endAt.formatted(date: .omitted, time: .shortened)
                    planned.append((fireAt, request(
                        id: "nudge.\(item.id)-\(stage.rawValue)", item: item, body: body, at: fireAt, now: now
                    )))
                }
            }
        }

        return planned.sorted { $0.0 < $1.0 }.prefix(Self.limit).map(\.1)
    }

    private func request(id: String, item: WorkItem, body: String, at fireAt: Date, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = item.id.description
        // Focus silences normal nudges; P1 breaks through (FR-44).
        content.interruptionLevel = item.priority == .urgent ? .timeSensitive : .active
        content.userInfo = [Self.itemIdKey: item.id.description]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireAt.timeIntervalSince(now)), repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    // MARK: - UNUserNotificationCenterDelegate

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let raw = response.notification.request.content.userInfo[Self.itemIdKey] as? String
        await handle(action: action, raw: raw)
    }

    func handle(action: String, raw: String?) async {
        guard let id = raw.flatMap(UUID.init(uuidString:)).map(UUIDv7.init) else { return }
        switch action {
        case Action.complete:
            _ = try? await CompleteTask(
                repository: environment.workItems, linkRepository: environment.links
            ).execute(id, at: .now)
        case Action.tomorrow:
            _ = try? await MoveToTomorrow(
                repository: environment.workItems, calendar: environment.workCalendar
            ).execute(id, at: .now)
        default:
            if let onOpen { onOpen(id) } else { pendingOpen = id }
        }
        NotificationCenter.default.post(name: TodayFlowEvents.itemsChanged, object: nil)
        await refresh()
    }
}
#endif
