import SwiftUI
import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// "Completed history" (driver.md FR-16): every finished task, newest first.
@MainActor
@Observable
public final class CompletedHistoryViewModel {
    public private(set) var items: [WorkItem] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.onOpenDetail = onOpenDetail
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let all = await repository.allItems()
        items = all
            .filter { $0.status == .done }
            .sorted {
                let left = $0.completedAt ?? $0.updatedAt
                let right = $1.completedAt ?? $1.updatedAt
                if left != right { return left > right }
                return $0.displayOrder < $1.displayOrder
            }
    }
}

public struct CompletedHistoryView: View {
    private let model: CompletedHistoryViewModel

    public init(model: CompletedHistoryViewModel) {
        self.model = model
    }

    @MainActor
    public init(
        repository: any WorkItemRepository,
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        model = CompletedHistoryViewModel(
            repository: repository,
            onOpenDetail: onOpenDetail
        )
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Completed", systemImage: "checkmark.circle")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(model.items.count) done")
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
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No completed tasks yet")
                        .font(.body.weight(.medium))
                    Text("Finished tasks appear here with their completion date.")
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
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: "#0ca30c"))

                                    Text(item.title)
                                        .strikethrough()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    Text((item.completedAt ?? item.updatedAt), format: .dateTime.day().month(.abbreviated).year())
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
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 420, height: 520)
        .task { await model.load() }
    }
}
