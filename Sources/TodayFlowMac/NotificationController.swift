#if canImport(AppKit)
import AppKit
import Foundation
import UserNotifications
import TodayFlowCore

/// Schedules the day's nudges and handles their actions (driver.md FR-42/FR-44).
///
/// The pure schedule lives in `NudgePlanner` (TodayFlowCore); this adapter owns
/// the `UNUserNotificationCenter` side: authorization, category registration,
/// request scheduling, and the Mark done / Snooze 15 min / Move to tomorrow
/// actions. `refresh()` is cheap and idempotent — the app calls it whenever the
/// day changes so completing a task removes its pending reminders.
@MainActor
public final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    /// Notification action identifiers (also used in tests).
    public enum Action {
        public nonisolated static let markDone = "TODAYFLOW_MARK_DONE"
        public nonisolated static let snooze15 = "TODAYFLOW_SNOOZE_15"
        public nonisolated static let moveToTomorrow = "TODAYFLOW_MOVE_TOMORROW"
    }

    public nonisolated static let categoryID = "TODAYFLOW_TASK"
    /// Summary nudges have no actions; tapping opens Today.
    public nonisolated static let summaryCategoryID = "TODAYFLOW_SUMMARY"
    public nonisolated static let itemIdKey = "itemId"

    private let center: UNUserNotificationCenter
    private let repository: any WorkItemRepository
    private let linkRepository: any LinkRepository
    private let reminders: (any ReminderRepository)?
    private let deviceId: String
    private let clock: @Sendable () -> Date
    private var calendar: WorkCalendar
    private var planner: NudgePlanner

    /// Opens the Today panel when a notification is clicked.
    public var onOpen: (@MainActor () -> Void)?

    public private(set) var isAuthorized = false

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        reminders: (any ReminderRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        planner: NudgePlanner = NudgePlanner(),
        clock: @escaping @Sendable () -> Date = { .now },
        center: UNUserNotificationCenter = .current(),
        onOpen: (@MainActor () -> Void)? = nil
    ) {
        self.center = center
        self.repository = repository
        self.linkRepository = linkRepository
        self.reminders = reminders
        self.calendar = calendar
        self.deviceId = deviceId
        self.planner = planner
        self.clock = clock
        self.onOpen = onOpen
        super.init()

        center.delegate = self
        registerCategories()
    }

    /// Registers the actions shown on a task notification (FR-42).
    public func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: Action.markDone, title: "Mark done"),
            UNNotificationAction(identifier: Action.snooze15, title: "Snooze 15 min"),
            UNNotificationAction(identifier: Action.moveToTomorrow, title: "Move to tomorrow"),
        ]
        let taskCategory = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        let summaryCategory = UNNotificationCategory(
            identifier: Self.summaryCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([taskCategory, summaryCategory])
    }

    /// Asks for alert/sound permission. Safe to call on every launch; macOS
    /// only shows the prompt once and returns the existing decision after that.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            isAuthorized = false
        }
        return isAuthorized
    }

    /// Business hours can change in Settings; rebuild the schedule next refresh.
    public func updateCalendar(_ calendar: WorkCalendar) {
        self.calendar = calendar
    }

    /// Recomputes and replaces this app's pending nudges.
    ///
    /// Only our own identifiers (`eod.` / `task.`) are removed, so a snoozed
    /// notification (a unique `snooze.` request) survives.
    public func refresh() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        else { return }

        let pending = await center.pendingNotificationRequests()
        let ours = pending
            .map(\.identifier)
            .filter {
                $0.hasPrefix("eod.") || $0.hasPrefix("task.") || $0.hasPrefix("custom.")
            }
        if !ours.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }

        let now = clock()
        let day = calendar.calendar.startOfDay(for: now)
        let result = await TodayQuery(repository: repository, calendar: calendar)
            .execute(on: day, at: now)

        let customReminders = await reminders?.pending(after: now) ?? []
        let customItems: [(Reminder, WorkItem)] = await withTaskGroup(
            of: (Reminder, WorkItem)?.self
        ) { group in
            for reminder in customReminders where reminder.kind == .task {
                group.addTask { [repository] in
                    guard let id = reminder.itemId,
                          let item = await repository.item(id),
                          !item.status.isTerminal
                    else { return nil }
                    return (reminder, item)
                }
            }
            var pairs: [(Reminder, WorkItem)] = []
            for await pair in group {
                if let pair { pairs.append(pair) }
            }
            return pairs.sorted { $0.0.fireAt < $1.0.fireAt }
        }
        let customItemIds = Set(customItems.compactMap { $0.0.itemId })

        // A task with an explicit reminder should not also get the automatic
        // 30-minute nudge.
        let nudges = planner
            .plan(openItems: result.all, calendar: calendar, now: now)
            .filter { nudge in
                if case .task(let id) = nudge.kind {
                    return !customItemIds.contains(id)
                }
                return true
            }

        for (reminder, item) in customItems {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = "Reminder · due at \(item.endAt.formatted(date: .omitted, time: .shortened))"
            content.sound = .default
            content.categoryIdentifier = Self.categoryID
            content.interruptionLevel = item.priority == .urgent ? .timeSensitive : .active
            content.userInfo = [Self.itemIdKey: item.id.description]

            let interval = reminder.fireAt.timeIntervalSince(now)
            guard interval > 0 else { continue }
            let request = UNNotificationRequest(
                identifier: "custom.\(reminder.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
            )
            try? await center.add(request)
        }

        for nudge in nudges {
            let interval = nudge.fireAt.timeIntervalSince(now)
            guard interval > 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            content.categoryIdentifier = nudge.itemId == nil
                ? Self.summaryCategoryID
                : Self.categoryID
            // FR-44: Focus silences normal nudges; P1 breaks through.
            content.interruptionLevel = nudge.isUrgent ? .timeSensitive : .active
            if let itemId = nudge.itemId {
                content.userInfo = [Self.itemIdKey: itemId.description]
            }

            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, interval),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: nudge.id,
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show nudges even while TodayFlow is frontmost.
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let itemId = (info[NotificationController.itemIdKey] as? String)
            .flatMap(UUID.init(uuidString:))
            .map(UUIDv7.init)

        if action == NotificationController.Action.snooze15 {
            await Self.snooze(response.notification.request.content)
            return
        }
        await handle(action: action, itemId: itemId)
    }

    /// Re-posts the same notification 15 minutes later. Nonisolated: the
    /// content is not `Sendable`, so it is copied and scheduled in one region.
    private nonisolated static func snooze(_ content: UNNotificationContent) async {
        guard let copy = content.mutableCopy() as? UNMutableNotificationContent else { return }
        let request = UNNotificationRequest(
            identifier: "snooze.\(UUID().uuidString)",
            content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func handle(action: String, itemId: UUIDv7?) async {
        switch action {
        case Action.markDone:
            if let itemId {
                _ = try? await CompleteTask(
                    repository: repository,
                    linkRepository: linkRepository,
                    deviceId: deviceId
                ).execute(itemId, at: clock())
            }
        case Action.moveToTomorrow:
            if let itemId {
                _ = try? await MoveToTomorrow(
                    repository: repository,
                    calendar: calendar,
                    deviceId: deviceId
                ).execute(itemId, at: clock())
            }
        default:
            // Notification click: bring the day forward.
            onOpen?()
        }
        await refresh()
    }
}
#endif
