#if canImport(AppKit)
import AppKit
import Foundation

/// Transparent overlay on the menu-bar button that accepts file/URL/text/image
/// drags (driver.md FR-01) and forwards clicks to the status-item controller.
///
/// `NSStatusBarButton` is created by the system and cannot be subclassed, so
/// the drop destination is a zero-impact subview. It draws nothing and keeps
/// the button's own image/title visible.
@MainActor
final class StatusDropView: NSView {
    /// Called with `isRightClick` when the user clicks the status item.
    var onClick: ((Bool) -> Void)?
    /// True when the pasteboard contains a supported object.
    var canDrop: ((NSPasteboard) -> Bool)?
    /// Performs the drop; returns whether it was accepted.
    var onDrop: ((NSPasteboard) -> Bool)?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    // MARK: - Click forwarding

    override func mouseDown(with event: NSEvent) {
        // Consume the down event so the overlay owns the click sequence; the
        // button action fires on mouse-up, matching the system status item.
    }

    override func mouseUp(with event: NSEvent) {
        onClick?(false)
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?(true)
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canDrop?(sender.draggingPasteboard) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }

    private func dragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        (canDrop?(sender.draggingPasteboard) ?? false) ? .copy : []
    }
}
#endif
