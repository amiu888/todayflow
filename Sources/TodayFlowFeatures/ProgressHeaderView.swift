import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

public struct ProgressHeaderView: View {
    public let progress: TodayQuery.Progress
    public let motion: Motion

    public init(progress: TodayQuery.Progress,
                motion: Motion = Motion(preference: .full)) {
        self.progress = progress
        self.motion = motion
    }

    public var body: some View {
        HStack(spacing: 7) {
            ProgressRingView(
                model: ProgressRingModel(done: progress.done, total: progress.total),
                size: 20,
                tint: ringTint,
                motion: motion
            )

            Text("\(progress.done)/\(progress.total) done")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Text(progress.isCleared
                ? "Day cleared"
                : "\(progress.remaining) left · " + TimeLeft.format(progress.secondsUntilEOB))
                .font(.caption2)
                .foregroundStyle(
                    progress.isCleared ? Color(hex: "#0ca30c") : DesignTokens.Palette.textSecondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if progress.overdue > 0 {
                overdueBadge
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceLabel)
    }

    private var ringTint: Color {
        if progress.isCleared {
            return Color(hex: "#0ca30c")
        } else if progress.overdue > 0 {
            return Color(hex: "#d03b3b")
        } else {
            return DesignTokens.Palette.accent
        }
    }

    private var overdueBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#fab219"))

            Text("\(progress.overdue)")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color(hex: "#fab219"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(hex: "#fab219").opacity(0.18)))
    }

    private var voiceLabel: String {
        var label = "\(progress.done) of \(progress.total) tasks done, \(progress.remaining) left, \(TimeLeft.format(progress.secondsUntilEOB)) until end of business"

        if progress.overdue > 0 {
            label += ", \(progress.overdue) overdue"
        }

        if progress.isCleared {
            label += ", day cleared"
        }

        return label
    }
}
