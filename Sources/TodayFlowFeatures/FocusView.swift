import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The focused-work window: a large timer, the current task, and only the
/// actions that matter (pause, +5, done, close).
public struct FocusView: View {
    private let model: FocusViewModel
    @Environment(\.colorScheme) private var colorScheme

    public init(model: FocusViewModel) {
        self.model = model
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Focus", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                Spacer()
                Button {
                    model.close()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Close focus mode")
                .accessibilityLabel("Close focus mode")
            }

            Spacer(minLength: 0)

            timerRing

            VStack(spacing: 5) {
                Text(model.item?.title ?? "Task")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .lineLimit(3)

                if let item = model.item {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PriorityColor.color(for: item.priority, in: colorScheme))
                            .frame(width: 7, height: 7)
                        Text(item.priority.label)
                        Text("·")
                        Text(item.endAt.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(
                                model.isOverdue
                                    ? DesignTokens.Palette.danger
                                    : DesignTokens.Palette.textSecondary
                            )
                    }
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
            }

            if model.isFinished {
                Text("Time’s up — take a breath, then keep going or finish.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.warning)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    model.toggleTimer()
                } label: {
                    Label(
                        model.isRunning ? "Pause" : (model.isFinished ? "Start again" : "Resume"),
                        systemImage: model.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help(model.isRunning ? "Pause the timer" : "Start the timer")

                Button("+5 min") {
                    model.extend()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Extend this focus session by five minutes")
            }

            HStack(spacing: 8) {
                Button {
                    Task { await model.complete() }
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(DesignTokens.Palette.success)
                .help("Complete this task")

                Button("Close") {
                    model.close()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .help("Close without completing")
            }

            if let error = model.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(width: 420, height: 500)
        .background(DesignTokens.Palette.background)
        .background(alignment: .top) {
            DesignTokens.Palette.aurora.frame(height: 300)
        }
        .overlay(alignment: .top) { WindowDragGrabber() }
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
    }

    @MainActor
    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(DesignTokens.Palette.hairline, lineWidth: 8)

            Circle()
                .trim(from: 0, to: model.fraction)
                .stroke(
                    AngularGradient(
                        colors: [
                            DesignTokens.Palette.accent,
                            DesignTokens.Palette.violet,
                            DesignTokens.Palette.accent,
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.fraction)

            VStack(spacing: 2) {
                Text(model.timeText)
                    .font(.system(size: 48, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .contentTransition(.numericText())

                Text(model.isRunning ? "focused" : (model.isFinished ? "session complete" : "paused"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
        }
        .frame(width: 210, height: 210)
        .help("Time remaining in this focus session")
    }
}
