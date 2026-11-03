import SwiftUI
import TodayFlowCore

/// The header progress ring (driver.md §4: "one glance: ring + count always
/// visible even collapsed", "ring advances with a spring").
public struct ProgressRingView: View {
    let model: ProgressRingModel
    let size: CGFloat
    let tint: Color
    let motion: Motion

    public init(
        model: ProgressRingModel,
        size: CGFloat = DesignTokens.Ring.diameter,
        tint: Color = .accentColor,
        motion: Motion = Motion(preference: .full)
    ) {
        self.model = model
        self.size = size
        self.tint = tint
        self.motion = motion
    }

    public var body: some View {
        let spring = motion.spring(for: .ring)
        let animation = spring.map {
            Animation.spring(response: $0.response, dampingFraction: $0.damping, blendDuration: 0)
        }
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: DesignTokens.Ring.lineWidth)
            Circle()
                .trim(from: 0, to: model.fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: DesignTokens.Ring.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // A round line cap can render a dot at zero length; hide it.
                .opacity(model.fraction > 0 ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(animation, value: model.fraction)
        .accessibilityElement()
        .accessibilityLabel(Text("\(model.done) of \(model.total) tasks done"))
    }
}

/// The row's priority dot (driver.md §4: "priority dot (P1 red, P2 orange,
/// P3 yellow, P4 grey)").
public struct PriorityDotView: View {
    let priority: Priority
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(priority: Priority, size: CGFloat = 8) {
        self.priority = priority
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(PriorityColor.color(for: priority, in: colorScheme))
            .frame(width: size, height: size)
            .accessibilityLabel(Text(priority.label))
    }
}

/// The SF Symbol fallback for an attachment icon (driver.md §4: "real system
/// icon where available + bundled SF Symbol fallback"). The app target swaps
/// in NSWorkspace system icons, image thumbnails, and favicons where it can;
/// this view is what renders when it cannot.
public struct AttachmentIconView: View {
    let attachment: Attachment
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(attachment: Attachment, size: CGFloat = 14) {
        self.attachment = attachment
        self.size = size
    }

    public var body: some View {
        let style = AttachmentIconStyle.style(for: attachment)
        Image(systemName: style.symbolName)
            .font(.system(size: size))
            .foregroundStyle(style.tint(in: colorScheme))
            .accessibilityLabel(
                Text(attachment.displayName.isEmpty ? style.accessibilityName : attachment.displayName)
            )
    }
}
