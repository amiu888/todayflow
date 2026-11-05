#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowDesign

/// A transparent strip that lets a borderless/SwiftUI window be dragged from
/// its header, even when the content fills the window.
public struct WindowDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        DragView()
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

/// A small visible grabber for the top of a floating form.
public struct WindowDragGrabber: View {
    public init() {}

    public var body: some View {
        Capsule()
            .fill(DesignTokens.Palette.textSecondary.opacity(0.35))
            .frame(width: 38, height: 4)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(WindowDragHandle())
            .accessibilityHidden(true)
    }
}
#endif
