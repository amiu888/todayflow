import Foundation
import Observation
import TodayFlowCore

/// The single source of truth for the menu-bar item and the slim bar
/// (driver.md FR-40): today's progress + the next open task, refreshed on a
/// timer. Both surfaces read the same values.
@MainActor
@Observable
public final class TodaySummaryModel {
    public private(set) var progress: TodayQuery.Progress
    public private(set) var nextTitle: String?

    /// Fires after every refresh with the new progress (the delegate routes
    /// it to the status item, which cannot observe SwiftUI state).
    @ObservationIgnored public var onRefreshed: ((TodayQuery.Progress) -> Void)?

    /// Fires once per day when end of business passes with tasks still open
    /// (driver.md FR-43). The delegate presents the review sheet.
    @ObservationIgnored public var onEndOfDay: (() -> Void)?

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private var calendar: WorkCalendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastEndOfDayReviewDay: Date?

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
        self.progress = TodayQuery.Result.empty.progress
        self.nextTitle = nil
    }

    /// Business hours can change in Settings; the delegate propagates the
    /// refreshed calendar after `loadSettings()`.
    public func updateCalendar(_ calendar: WorkCalendar) {
        self.calendar = calendar
    }

    /// Re-runs the Today query at the current clock and publishes the result.
    public func refresh() async {
        let now = clock()
        let day = calendar.calendar.startOfDay(for: now)
        let result = await TodayQuery(repository: repository, calendar: calendar)
            .execute(on: day, at: now)
        progress = result.progress
        nextTitle = result.all.first?.title

        let isWorkday = calendar.isWorkingDay(now)
        let endOfBusiness = calendar.endOfBusiness(for: now)
        if isWorkday,
           now >= endOfBusiness,
           result.progress.remaining > 0,
           lastEndOfDayReviewDay != day
        {
            lastEndOfDayReviewDay = day
            onEndOfDay?()
        }

        onRefreshed?(progress)
    }

    /// Polls `refresh()` on an interval; the menu bar is not a repository
    /// observer, so a light poll keeps the count and ring current.
    public func startPolling(every seconds: Double = 30) {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
