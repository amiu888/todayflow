#if canImport(AppKit)
import AppKit
import SwiftUI

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
            guard let window,
                  event.window === window,
                  window.isKeyWindow,
                  // A sheet or alert on top owns the keyboard.
                  window.attachedSheet == nil,
                  PasteCatcher.isPasteShortcut(
                      characters: event.charactersIgnoringModifiers,
                      modifiers: event.modifierFlags
                  ),
                  let onPaste
            else { return false }
            let isEditingText = window.firstResponder is NSTextView
            return onPaste(isEditingText)
        }
    }
}
#endif
