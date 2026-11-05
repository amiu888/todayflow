#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TodayFlowCore

/// An AppKit drag source and click target for a task's title area.
///
/// SwiftUI's `.onDrag` hands the drag system a lazy `NSItemProvider`; when the
/// drop happens the provider can already be gone, leaving an empty pasteboard.
/// This view writes the payload into an `NSPasteboardItem` directly and starts
/// an `NSDraggingSession`, so the drop target can always read it.
public struct TaskDragSource: NSViewRepresentable {
    public struct MenuAction {
        public let title: String
        public let isSeparator: Bool
        public let handler: @MainActor () -> Void

        public init(
            _ title: String,
            isSeparator: Bool = false,
            handler: @escaping @MainActor () -> Void = {}
        ) {
            self.title = title
            self.isSeparator = isSeparator
            self.handler = handler
        }

        public static var separator: MenuAction {
            MenuAction("", isSeparator: true)
        }
    }

    private let itemId: UUIDv7
    private let sourceTray: UUIDv7?
    private let title: String
    private let tooltip: String?
    private let onHover: @MainActor (Bool) -> Void
    private let onClick: @MainActor () -> Void
    private let menuActions: [MenuAction]

    public init(
        itemId: UUIDv7,
        sourceTray: UUIDv7? = nil,
        title: String,
        tooltip: String? = nil,
        onHover: @escaping @MainActor (Bool) -> Void = { _ in },
        onClick: @escaping @MainActor () -> Void,
        menuActions: [MenuAction] = []
    ) {
        self.itemId = itemId
        self.sourceTray = sourceTray
        self.title = title
        self.tooltip = tooltip
        self.onHover = onHover
        self.onClick = onClick
        self.menuActions = menuActions
    }

    public func makeNSView(context: Context) -> DragView {
        let view = DragView(
            itemId: itemId,
            sourceTray: sourceTray,
            title: title,
            tooltip: tooltip
        )
        view.onHover = onHover
        view.onClick = onClick
        view.menuActions = menuActions.map(\.handler)
        view.menuTitles = menuActions
        return view
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: DragView,
        context: Context
    ) -> CGSize? {
        // The drag view draws nothing and has no intrinsic size; without this
        // SwiftUI lays it out at 0×0 and it never receives a mouse event.
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    public func updateNSView(_ view: DragView, context: Context) {
        view.onHover = onHover
        view.onClick = onClick
        view.menuActions = menuActions.map(\.handler)
        view.menuTitles = menuActions
        view.toolTip = tooltip
    }

    @MainActor
    public final class DragView: NSView, NSDraggingSource {
        private let itemId: UUIDv7
        private let sourceTray: UUIDv7?
        private let title: String

        var onHover: (@MainActor (Bool) -> Void)?
        var onClick: (@MainActor () -> Void)?
        var menuActions: [@MainActor () -> Void] = []
        var menuTitles: [MenuAction] = []

        private var mouseDownEvent: NSEvent?
        private var didDrag = false
        private var tracking: NSTrackingArea?

        init(itemId: UUIDv7, sourceTray: UUIDv7?, title: String, tooltip: String?) {
            self.itemId = itemId
            self.sourceTray = sourceTray
            self.title = title
            super.init(frame: .zero)
            self.toolTip = tooltip
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel(title)
            setAccessibilityIdentifier("task-drag-area-\(title)")
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                removeTrackingArea(tracking)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            tracking = area
        }

        public override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        public override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        public override func mouseDown(with event: NSEvent) {
            Diagnostics.log("drag", "mouseDown title=\(title)")
            mouseDownEvent = event
            didDrag = false
        }

        public override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let start = mouseDownEvent else { return }
            let dx = event.locationInWindow.x - start.locationInWindow.x
            let dy = event.locationInWindow.y - start.locationInWindow.y
            guard hypot(dx, dy) > 4 else { return }

            didDrag = true
            Diagnostics.log("drag", "drag start title=\(title)")
            let pasteboardItem = WorkItemDragPayload.pasteboardItem(
                for: itemId,
                sourceTray: sourceTray
            )
            let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
            item.setDraggingFrame(bounds, contents: dragImage())
            beginDraggingSession(with: [item], event: event, source: self)
        }

        public override func mouseUp(with event: NSEvent) {
            defer { mouseDownEvent = nil }
            guard !didDrag else { return }
            onClick?()
        }

        public override func rightMouseDown(with event: NSEvent) {
            guard !menuTitles.isEmpty else { return }
            let menu = NSMenu()
            for (index, action) in menuTitles.enumerated() {
                if action.isSeparator {
                    menu.addItem(.separator())
                    continue
                }
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(runMenuAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                menu.addItem(item)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        public override func scrollWheel(with event: NSEvent) {
            // Keep the surrounding SwiftUI scroll view scrolling normally.
            super.scrollWheel(with: event)
        }

        @objc
        private func runMenuAction(_ sender: NSMenuItem) {
            guard sender.tag >= 0, sender.tag < menuActions.count else { return }
            menuActions[sender.tag]()
        }

        public func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        public func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        public func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            mouseDownEvent = nil
            didDrag = false
        }

        private func dragImage() -> NSImage {
            let size = NSSize(width: 220, height: 28)
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
                (self.title as NSString).draw(
                    at: NSPoint(x: 9, y: 7),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 12),
                        .foregroundColor: NSColor.labelColor,
                    ]
                )
                return true
            }
            return image
        }
    }
}
#endif
