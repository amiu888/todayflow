import SwiftUI
import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// "Upcoming" (driver.md FR-16): the next seven days, by due time.
@MainActor
@Observable
public final class UpcomingViewModel {
    public private(set) var items: [WorkItem] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        clock: @escaping @Sendable () -> Date = { .now },
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
        self.onOpenDetail = onOpenDetail
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let today = calendar.calendar.startOfDay(for: clock())
        let end = calendar.calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let all = await repository.allItems()
        items = all
            .filter {
                !$0.isDeleted
                    && !$0.status.isTerminal
                    && $0.endAt >= today
                    && $0.endAt < end
            }
            .sorted {
                if $0.endAt != $1.endAt { return $0.endAt < $1.endAt }
                return $0.displayOrder < $1.displayOrder
            }
    }
}

public struct UpcomingView: View {
    private let model: UpcomingViewModel

    @Environment(\.colorScheme) private var colorScheme

    public init(model: UpcomingViewModel) {
        self.model = model
    }

    /// Convenience for the Mac app layer.
    @MainActor
    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        model = UpcomingViewModel(
            repository: repository,
            calendar: calendar,
            onOpenDetail: onOpenDetail
        )
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Upcoming", systemImage: "calendar")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Next 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            if model.isLoading && model.items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Nothing coming up")
                        .font(.body.weight(.medium))
                    Text("Tasks due in the next seven days appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.items) { item in
                            Button {
                                model.onOpenDetail?(item.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(PriorityColor.color(for: item.priority, in: colorScheme))
                                        .frame(width: 8, height: 8)

                                    Text(item.title)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(item.endAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: DesignTokens.Spacing.rowHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.03))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.title), due \(item.endAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                    }
                    .padding(12)
                }
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(12)
            }
        }
        .frame(width: 420, height: 520)
        .task { await model.load() }
    }
}
