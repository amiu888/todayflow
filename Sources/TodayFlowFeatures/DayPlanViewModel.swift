import Foundation
import Observation
import TodayFlowCore

/// "Plan my day" (driver.md §8): asks the AI for an order, shows the reasons,
/// and applies it only when the user accepts.
@MainActor
@Observable
public final class DayPlanViewModel {
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUIDv7
        public let title: String
        public let reason: String
        public let priority: Priority
        public let dueAt: Date

        public init(
            id: UUIDv7,
            title: String,
            reason: String,
            priority: Priority,
            dueAt: Date
        ) {
            self.id = id
            self.title = title
            self.reason = reason
            self.priority = priority
            self.dueAt = dueAt
        }
    }

    public private(set) var rows: [Row] = []
    public private(set) var summary: String = ""
    public private(set) var isLoading = false
    public private(set) var isApplying = false
    public private(set) var lastError: String?

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let assistant: any AIAssistant
    @ObservationIgnored public var onFinished: (@MainActor () -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        assistant: any AIAssistant,
        clock: @escaping @Sendable () -> Date = { .now },
        onFinished: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.calendar = calendar
        self.deviceId = deviceId
        self.assistant = assistant
        self.clock = clock
        self.onFinished = onFinished
    }

    /// Loads today's open tasks, then asks for a plan.
    public func loadAndPlan() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        summary = ""
        rows = []

        let now = clock()
        let day = calendar.calendar.startOfDay(for: now)
        let result = await TodayQuery(repository: repository, calendar: calendar)
            .execute(on: day, at: now)
        let items = result.all
        guard !items.isEmpty else {
            lastError = "There are no open tasks to plan."
            return
        }

        do {
            let plan = try await assistant.planDay(items, hours: calendar)
            summary = plan.summary
            rows = plan.order.compactMap { entry in
                guard let item = items.first(where: { $0.id == entry.itemId }) else {
                    return nil
                }
                return Row(
                    id: item.id,
                    title: item.title,
                    reason: entry.reason,
                    priority: item.priority,
                    dueAt: item.endAt
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Persists the proposed order as the Today list's manual sort.
    public func apply() async {
        guard !rows.isEmpty, !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        lastError = nil

        let reorder = ReorderTask(repository: repository, deviceId: deviceId)
        var previous: String?
        do {
            for row in rows {
                let key = FractionalIndex.midpoint(previous, nil)
                try await reorder.execute(row.id, newDisplayOrder: key, at: clock())
                previous = key
            }
            onFinished?()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func dismiss() {
        onFinished?()
    }
}
