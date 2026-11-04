import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The slim bar surface (driver.md lines 145-152: "Slim bar 360×44"): a
/// one-line glance — progress ring, remaining count, next task, time left.
///
/// Takes the model (not values) so Observation tracks the reads in `body`
/// and the bar re-renders on every refresh.
public struct SlimBarView: View {
    public let summary: TodaySummaryModel
    public let onOpen: () -> Void
    public let onDismiss: () -> Void

    public init(summary: TodaySummaryModel, onOpen: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.summary = summary
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    public var body: some View {
        let progress = summary.progress
        return HStack(spacing: 10) {
            ProgressRingView(model: ProgressRingModel(done: progress.done, total: progress.total))
            VStack(alignment: .leading, spacing: 1) {
                Text(progress.isCleared ? "Day cleared" : "\(progress.remaining) left")
                    .font(.caption)
                    .fontWeight(.semibold)
                if let nextTitle = summary.nextTitle {
                    Text(nextTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(TimeLeft.format(progress.secondsUntilEOB))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
