#if os(macOS)
// Mac-only screen; the iPhone app has its own (TodayFlowPhone).
#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore

/// Routes ⌘V in the hosting window to `onPaste`, so a copied image, file, or
/// link can be attached to a task wherever the keyboard focus is.
///
/// SwiftUI's `.onPasteCommand` only fires for a focused non-text view, and a
/// focused text field swallows ⌘V even when the clipboard holds an image it
/// cannot use. A local key monitor sees the key first; the handler decides
/// whether to consume it. Returning `false` leaves the normal text paste alone.
public struct PasteCatcher: NSViewRepresentable {
    /// `isEditingText` is true when a text field or editor has keyboard focus.
    /// Return true when the paste was handled and must not reach the field.
    private let onPaste: @MainActor (_ isEditingText: Bool) -> Bool

    public init(onPaste: @escaping @MainActor (_ isEditingText: Bool) -> Bool) {
        self.onPaste = onPaste
    }

    public func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onPaste = onPaste
        return view
    }

    public func updateNSView(_ view: MonitorView, context: Context) {
        view.onPaste = onPaste
    }

    public static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.stopMonitoring()
    }

    /// True for a plain ⌘V (no Shift/Option/Control), on any keyboard layout.
    nonisolated static func isPasteShortcut(
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let relevant = modifiers.intersection([.command, .shift, .option, .control])
        return relevant == .command && characters?.lowercased() == "v"
    }

    @MainActor
    public final class MonitorView: NSView {
        var onPaste: (@MainActor (Bool) -> Bool)?
        private var monitor: Any?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopMonitoring()
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    // Local monitors always run on the main thread.
                    nonisolated(unsafe) let event = event
                    let consumed = MainActor.assumeIsolated {
                        self?.handles(event) ?? false
                    }
                    return consumed ? nil : event
                }
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handles(_ event: NSEvent) -> Bool {
            guard PasteCatcher.isPasteShortcut(
                characters: event.charactersIgnoringModifiers,
                modifiers: event.modifierFlags
            ) else { return false }
            guard let window, let onPaste else { return false }
            // Key events are delivered to the key window; some panels report
            // no event window, so fall back to the key-window check.
            let isOurs = event.window === window
                || (event.window == nil && window.isKeyWindow)
            guard isOurs,
                  // A sheet or alert on top owns the keyboard.
                  window.attachedSheet == nil
            else { return false }
            let isEditingText = window.firstResponder is NSTextView
            let handled = onPaste(isEditingText)
            // Type names only (no contents) so a failed paste can be diagnosed.
            let types = (NSPasteboard.general.types ?? []).map(\.rawValue)
                .filter { !$0.hasPrefix("dyn.") }.prefix(8).joined(separator: ",")
            Diagnostics.log(
                "paste",
                "cmd-V window=\(window.title) editingText=\(isEditingText) handled=\(handled) types=[\(types)]"
            )
            return handled
        }
    }
}
#endif
#endif
