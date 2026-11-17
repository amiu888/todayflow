import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The due-soon popup: a small clock character that hops in from the screen
/// edge and gets more agitated as the deadline gets closer.
public struct DueNudgeView: View {
    public static let cardSize = CGSize(width: 340, height: 104)
    /// Room around the card for the hop and the shadow.
    public static let panelSize = CGSize(width: 372, height: 148)

    private let nudge: DueNudge
    private let onOpen: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var shownAt = Date.now

    public init(
        nudge: DueNudge,
        onOpen: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.nudge = nudge
        self.onOpen = onOpen
        self.onDismiss = onDismiss
    }

    private var tint: Color {
        switch nudge.stage {
        case .twelveHours: DesignTokens.Palette.accent
        case .fiveHours: DesignTokens.Palette.warning
        case .oneHour: DesignTokens.Palette.danger
        }
    }

    private var headline: String {
        switch nudge.stage {
        case .twelveHours: "Psst… due in under 12 hours"
        case .fiveHours: "Tick-tock! A few hours left"
        case .oneHour: "Hurry! Less than an hour left"
        }
    }

    /// "Due 5:00 PM · in 4 h 58 min"
    static func dueLine(dueAt: Date, now: Date) -> String {
        let minutes = max(1, Int((dueAt.timeIntervalSince(now) / 60).rounded(.up)))
        let left = minutes < 60
            ? "\(minutes) min"
            : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
        return "Due \(dueAt.formatted(date: .omitted, time: .shortened)) · in \(left)"
    }

    /// How high the card is lifted at `t` seconds after it appeared. The
    /// 12-hour popup stays put, the 5-hour one hops twice, the 1-hour one
    /// keeps hopping every couple of seconds.
    static func hop(stage: DueNudgeStage, t: TimeInterval) -> CGFloat {
        let period: TimeInterval
        let rounds: Int?
        let height: CGFloat
        switch stage {
        case .twelveHours: return 0
        case .fiveHours: (period, rounds, height) = (2.4, 2, 9)
        case .oneHour: (period, rounds, height) = (1.8, nil, 13)
        }
        let start = 0.7 // after the slide-in settles
        guard t >= start else { return 0 }
        let local = t - start
        if let rounds, Int(local / period) >= rounds { return 0 }
        let phase = local.truncatingRemainder(dividingBy: period)
        let burst = 0.72 // two quick hops
        guard phase < burst else { return 0 }
        return abs(sin(phase / burst * 2 * .pi)) * height
    }

    @MainActor
    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSince(shownAt)
            card(t: t, now: context.date)
                .offset(y: -Self.hop(stage: nudge.stage, t: t))
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .offset(x: appeared || reduceMotion ? 0 : Self.panelSize.width + 40)
        .opacity(appeared ? 1 : 0)
        .frame(
            width: Self.panelSize.width,
            height: Self.panelSize.height,
            alignment: .bottom
        )
        .padding(.bottom, 0)
        .onAppear {
            shownAt = .now
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.55, dampingFraction: 0.58)
            ) {
                appeared = true
            }
        }
    }

    @MainActor
    private func card(t: TimeInterval, now: Date) -> some View {
        HStack(spacing: 12) {
            DueNudgeMascot(stage: nudge.stage, tint: tint, t: t)
                .frame(width: 60, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(nudge.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(Self.dueLine(dueAt: nudge.dueAt, now: now))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Button("Open") { onOpen() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(tint)
                    .help("Open this task")
                    .accessibilityIdentifier("due-nudge-open")
                Button("Later") { onDismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Hide this reminder")
                    .accessibilityIdentifier("due-nudge-dismiss")
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    tint.opacity(nudge.stage == .oneHour ? 0.55 + 0.35 * abs(sin(t * 3)) : 0.55),
                    lineWidth: nudge.stage == .oneHour ? 2 : 1.5
                )
        )
        .shadow(color: tint.opacity(0.28), radius: 12, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(headline). \(nudge.title). \(Self.dueLine(dueAt: nudge.dueAt, now: now))")
    }
}

/// A round alarm-clock character with eyes. Calm at twelve hours, worried at
/// five, ringing at one.
struct DueNudgeMascot: View {
    let stage: DueNudgeStage
    let tint: Color
    /// Seconds since the popup appeared; drives every motion.
    let t: TimeInterval

    private var isRinging: Bool {
        stage == .oneHour && t.truncatingRemainder(dividingBy: 1.8) < 0.9
    }

    private var tilt: Double {
        switch stage {
        case .twelveHours: sin(t * 1.6) * 4
        case .fiveHours: sin(t * 3.2) * 7
        case .oneHour: isRinging ? sin(t * 42) * 7 : sin(t * 3.2) * 4
        }
    }

    private var isBlinking: Bool {
        t.truncatingRemainder(dividingBy: 2.9) > 2.76
    }

    var body: some View {
        ZStack {
            if stage == .oneHour {
                // Ringing waves.
                ForEach(0..<2, id: \.self) { index in
                    let progress = (t * 0.9 + Double(index) * 0.5)
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(tint.opacity(0.5 * (1 - progress)), lineWidth: 2)
                        .frame(width: 44 + 22 * progress, height: 44 + 22 * progress)
                        .offset(y: 4)
                }
            }

            ZStack {
                // Bells.
                bell.offset(x: -15, y: -19).rotationEffect(.degrees(-28))
                bell.offset(x: 15, y: -19).rotationEffect(.degrees(28))
                // Feet.
                Capsule().fill(tint.opacity(0.85)).frame(width: 7, height: 10)
                    .rotationEffect(.degrees(24)).offset(x: -13, y: 23)
                Capsule().fill(tint.opacity(0.85)).frame(width: 7, height: 10)
                    .rotationEffect(.degrees(-24)).offset(x: 13, y: 23)

                // Body and face plate.
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 44)
                    .offset(y: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 35, height: 35)
                    .offset(y: 4)

                face.offset(y: 4)

                if stage == .oneHour {
                    // A sweat drop.
                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color(red: 0.35, green: 0.7, blue: 1))
                        .offset(x: 22, y: -8 + 5 * (t.truncatingRemainder(dividingBy: 1.2) / 1.2))
                        .opacity(1 - t.truncatingRemainder(dividingBy: 1.2) / 1.2)
                }
            }
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .offset(y: stage == .twelveHours ? sin(t * 2.2) * 1.5 : 0)
        }
        .accessibilityHidden(true)
    }

    private var bell: some View {
        Circle()
            .fill(tint)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
    }

    private var ink: Color { Color(red: 0.12, green: 0.14, blue: 0.2) }

    @ViewBuilder
    private var face: some View {
        // Eyes look toward the text; they widen as time runs out.
        let eye: CGFloat = stage == .oneHour ? 7 : 5.5
        HStack(spacing: stage == .oneHour ? 6 : 7) {
            eyeView(size: eye)
            eyeView(size: eye)
        }
        .offset(y: -4)

        // Cheeks.
        HStack(spacing: 20) {
            Circle().fill(Color.pink.opacity(0.45)).frame(width: 5, height: 5)
            Circle().fill(Color.pink.opacity(0.45)).frame(width: 5, height: 5)
        }
        .offset(y: 3)

        // Mouth.
        Group {
            switch stage {
            case .twelveHours:
                SmileShape()
                    .stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 10, height: 4)
            case .fiveHours:
                Ellipse().fill(ink).frame(width: 5, height: 5)
            case .oneHour:
                Ellipse().fill(ink).frame(width: 8, height: isRinging ? 9 : 6)
            }
        }
        .offset(y: 7)
    }

    private func eyeView(size: CGFloat) -> some View {
        Capsule()
            .fill(ink)
            .frame(width: size, height: isBlinking ? 1.2 : size)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.36, height: size * 0.36)
                    .offset(x: -size * 0.12, y: size * 0.12)
                    .opacity(isBlinking ? 0 : 1)
            }
            .frame(height: size)
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 2)
        )
        return path
    }
}
