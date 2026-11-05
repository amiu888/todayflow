import SwiftUI
import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// Completed-work insights and a small weekly review.
@MainActor
@Observable
public final class InsightsViewModel {
    public struct DayCount: Identifiable, Hashable, Sendable {
        public let date: Date
        public let count: Int
        public var id: Date { date }
    }

    public private(set) var daily: [DayCount] = []
    public private(set) var openCount = 0
    public private(set) var overdueCount = 0
    public private(set) var streak = 0

    public var weekTotal: Int {
        daily.suffix(7).map(\.count).reduce(0, +)
    }

    public var monthTotal: Int {
        daily.suffix(30).map(\.count).reduce(0, +)
    }

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(
        repository: any WorkItemRepository,
        calendar: Calendar = .current,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
    }

    public func load() async {
        let now = clock()
        let items = await repository.allItems()
        let today = calendar.startOfDay(for: now)
        let completed = items.filter { $0.status == .done && $0.completedAt != nil }

        daily = (0..<30).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 29, to: today)
            else { return nil }
            let count = completed.filter {
                calendar.isDate($0.completedAt!, inSameDayAs: date)
            }.count
            return DayCount(date: date, count: count)
        }

        openCount = items.filter { !$0.status.isTerminal }.count
        overdueCount = items.filter { !$0.status.isTerminal && $0.endAt < now }.count

        // A day with no completions yet does not break the streak until it is
        // over, so look back from today and fall back to yesterday.
        var cursor = today
        var run = 0
        if count(on: cursor) > 0 {
            while count(on: cursor) > 0 {
                run += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
                else { break }
                cursor = previous
            }
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
            while count(on: cursor) > 0 {
                run += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor)
                else { break }
                cursor = previous
            }
        }
        streak = run
    }

    private func count(on date: Date) -> Int {
        daily.first { calendar.isDate($0.date, inSameDayAs: date) }?.count ?? 0
    }
}

public struct InsightsView: View {
    private let model: InsightsViewModel

    public init(model: InsightsViewModel) {
        self.model = model
    }

    @MainActor
    public init(repository: any WorkItemRepository, calendar: Calendar = .current) {
        model = InsightsViewModel(repository: repository, calendar: calendar)
    }

    @MainActor
    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Insights", systemImage: "chart.bar.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Last 30 days")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            HStack(spacing: 10) {
                stat("\(model.weekTotal)", "this week")
                stat("\(model.monthTotal)", "this month")
                stat("\(model.streak)", model.streak == 1 ? "day streak" : "day streak")
            }

            chart

            HStack(spacing: 10) {
                Label("\(model.openCount) open", systemImage: "circle.dashed")
                if model.overdueCount > 0 {
                    Label("\(model.overdueCount) overdue", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.Palette.danger)
                }
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(DesignTokens.Palette.textSecondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 540, height: 430)
        .background(DesignTokens.Palette.background)
        .overlay(alignment: .top) { WindowDragGrabber() }
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
    }

    @MainActor
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, design: .rounded).weight(.bold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
    }

    @MainActor
    private var chart: some View {
        let maxCount = max(1, model.daily.map(\.count).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(model.daily.suffix(14)) { day in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            day.count == 0
                                ? AnyShapeStyle(DesignTokens.Palette.hairline)
                                : AnyShapeStyle(DesignTokens.Palette.gradient)
                        )
                        .frame(
                            height: max(4, CGFloat(day.count) / CGFloat(maxCount) * 90)
                        )
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.system(size: 7))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .help("\(day.count) completed on \(day.date.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        .frame(height: 120)
    }
}
