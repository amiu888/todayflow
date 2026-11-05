#if canImport(AppKit)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import TodayFlowCore

/// Hosts SwiftUI content and accepts task drags through AppKit's dragging
/// destination API. SwiftUI's `.onDrop` can run after the drag providers have
/// been invalidated, so the pasteboard read here happens while the drag is
/// still alive.
public struct TrayDropArea<Content: View>: NSViewRepresentable {
    private let content: Content
    private let onTargeted: @MainActor (Bool) -> Void
    private let onDrop: @MainActor ([WorkItemDragPayload]) -> Bool

    public init(
        onTargeted: @escaping @MainActor (Bool) -> Void = { _ in },
        onDrop: @escaping @MainActor ([WorkItemDragPayload]) -> Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.onTargeted = onTargeted
        self.onDrop = onDrop
    }

    public func makeNSView(context: Context) -> DropView {
        let view = DropView(rootView: content)
        view.onTargeted = onTargeted
        view.onDrop = onDrop
        return view
    }

    public func updateNSView(_ nsView: DropView, context: Context) {
        nsView.hosting.rootView = content
        nsView.onTargeted = onTargeted
        nsView.onDrop = onDrop
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: DropView,
        context: Context
    ) -> CGSize? {
        let fitting = nsView.hosting.fittingSize
        return CGSize(
            width: proposal.width ?? fitting.width,
            height: proposal.height ?? fitting.height
        )
    }

    @MainActor
    public final class DropView: NSView {
        let hosting: NSHostingView<Content>
        var onTargeted: (@MainActor (Bool) -> Void)?
        var onDrop: (@MainActor ([WorkItemDragPayload]) -> Bool)?

        private var isTargeted = false
        private var customType: NSPasteboard.PasteboardType {
            NSPasteboard.PasteboardType(UTType.todayFlowWorkItem.identifier)
        }

        init(rootView: Content) {
            self.hosting = NSHostingView(rootView: rootView)
            super.init(frame: .zero)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
                hosting.topAnchor.constraint(equalTo: topAnchor),
                hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            registerForDraggedTypes([customType, .string])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            Diagnostics.log(
                "drop",
                "enter types=\(sender.draggingPasteboard.types ?? [])"
            )
            let accepted = canAccept(sender)
            setTargeted(accepted)
            return accepted ? .copy : []
        }

        public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            let accepted = canAccept(sender)
            setTargeted(accepted)
            return accepted ? .copy : []
        }

        public override func draggingExited(_ sender: NSDraggingInfo?) {
            setTargeted(false)
        }

        public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            canAccept(sender)
        }

        public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            setTargeted(false)
            let pasteboard = sender.draggingPasteboard
            let payloads = WorkItemDragPayload.loadAll(from: pasteboard)
            Diagnostics.log(
                "drop",
                "appkit types=\(pasteboard.types ?? []) payloads=\(payloads.count)"
            )
            guard !payloads.isEmpty else { return false }
            return onDrop?(payloads) ?? false
        }

        private func canAccept(_ sender: NSDraggingInfo) -> Bool {
            let pasteboard = sender.draggingPasteboard
            let types = pasteboard.types ?? []
            if types.contains(customType) { return true }
            return !WorkItemDragPayload.loadAll(from: pasteboard).isEmpty
        }

        private func setTargeted(_ value: Bool) {
            guard value != isTargeted else { return }
            isTargeted = value
            onTargeted?(value)
        }
    }
}
#endif
