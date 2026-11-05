import Foundation
import Observation
import TodayFlowCore

/// The end-of-day review's brain (driver.md FR-43).
///
/// Loads the tasks that are still open, then lets the user resolve each one
/// with a single action: move it to tomorrow, pick another date, mark it done,
/// or keep it for today. The view is pure presentation; every mutation goes
/// through a Core use case so the same rules apply as on the Today list.
@MainActor
@Observable
public final class EndOfDayReviewViewModel {
    /// One unfinished task in the review.
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUIDv7
        public let title: String
        public let priority: Priority
        public let endAt: Date
        public let isOverdue: Bool

        public init(
            id: UUIDv7,
            title: String,
            priority: Priority,
            endAt: Date,
            isOverdue: Bool
        ) {
            self.id = id
            self.title = title
            self.priority = priority
            self.endAt = endAt
            self.isOverdue = isOverdue
        }
    }

    public private(set) var rows: [Row] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?
    /// The earliest date "Pick a date" offers: tomorrow. At end of business,
    /// today's end of business has already passed, so moving a task there
    /// would leave it immediately overdue.
    public private(set) var earliestDate: Date
    /// The "Pick a date" default (tomorrow).
    public private(set) var suggestedDate: Date

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let linkRepository: any LinkRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public var onFinished: (@MainActor () -> Void)?
    @ObservationIgnored private var hasFinished = false

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        onFinished: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
        self.onFinished = onFinished
        let today = calendar.calendar.startOfDay(for: clock())
        let tomorrow = calendar.calendar.date(byAdding: .day, value: 1, to: today) ?? today
        self.earliestDate = tomorrow
        self.suggestedDate = tomorrow
    }

    /// Loads today's unfinished tasks in display order.
    public func load() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let now = clock()
        let day = calendar.calendar.startOfDay(for: now)
        let result = await TodayQuery(repository: repository, calendar: calendar)
            .execute(on: day, at: now)

        rows = result.all.map { item in
            Row(
                id: item.id,
                title: item.title,
                priority: item.priority,
                endAt: item.endAt,
                isOverdue: item.endAt < now
            )
        }
        if rows.isEmpty {
            finish()
        }
    }

    /// FR-43 "Move to tomorrow": next working day's end of business.
    public func moveToTomorrow(_ id: UUIDv7) async {
        do {
            try await MoveToTomorrow(
                repository: repository,
                calendar: calendar,
                deviceId: deviceId
            ).execute(id, at: clock())
            remove(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// FR-43 "Pick a date": end of business on the chosen day.
    public func move(_ id: UUIDv7, to date: Date) async {
        do {
            try await RescheduleTask(
                repository: repository,
                calendar: calendar,
                deviceId: deviceId
            ).execute(id, to: date, at: clock())
            remove(id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// FR-43 "Done": complete the task through the normal use case, so chains
    /// and blocked prerequisites behave exactly as on the Today list.
    public func markDone(_ id: UUIDv7) async {
        do {
            try await CompleteTask(
                repository: repository,
                linkRepository: linkRepository,
                deviceId: deviceId
            ).execute(id, at: clock())
            remove(id)
        } catch CompleteTask.Error.blocked {
            lastError = "This task is blocked by an unfinished prerequisite."
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// FR-43 "Cancel"/"Keep": leave the task untouched and take it out of the
    /// review list. The review closes once every row is resolved.
    public func keep(_ id: UUIDv7) {
        remove(id)
    }

    /// Closes the review without touching the remaining tasks.
    public func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        onFinished?()
    }

    private func remove(_ id: UUIDv7) {
        guard rows.contains(where: { $0.id == id }) else { return }
        rows.removeAll { $0.id == id }
        if rows.isEmpty {
            finish()
        }
    }
}
