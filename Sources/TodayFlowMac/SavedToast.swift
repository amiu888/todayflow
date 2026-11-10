#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowDesign

/// A small "Saved" confirmation that floats where a window just closed and
/// fades out on its own. It never takes focus or blocks clicks.
@MainActor
enum SavedToast {
    private static var current: NSPanel?

    static func show(centeredOn frame: NSRect, message: String = "Saved", duration: TimeInterval = 0.5) {
        current?.orderOut(nil)

        let size = NSSize(width: 132, height: 44)
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: SavedToastView(message: message))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        current = panel

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard current === panel else { return }
            if reduceMotion {
                panel.orderOut(nil)
                current = nil
                return
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    if current === panel { current = nil }
                }
            })
        }
    }
}

private struct SavedToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DesignTokens.Palette.success)
            Text(message)
                .font(.body.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.Palette.hairline))
    }
}
#endif
