#if canImport(AppKit)
import AppKit

/// The mini progress ring for the menu-bar item (driver.md FR-40: the status
/// item shows the remaining count + a mini progress ring).
///
/// `Design.ProgressRingView` is SwiftUI-only, so the AppKit status item draws
/// its own ring with the same visual language (track + arc from the top).
public enum StatusItemIcon {
    /// Menu-bar icons are ~18 pt tall.
    public static let size: CGFloat = 18

    /// A template image: the system tints it for light/dark menu bars.
    public static func image(fraction: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.black.set()
            let lineWidth: CGFloat = 2
            let radius = min(rect.width, rect.height) / 2 - lineWidth
            let center = NSPoint(x: rect.midX, y: rect.midY)

            // Track: the full circle, always drawn.
            let track = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            track.lineWidth = lineWidth
            track.stroke()

            // Progress arc: from the top, clockwise.
            let f = min(1, max(0, fraction))
            if f > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * f,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
