#if canImport(AppKit)
import AppKit

/// Turns on continuous spell checking for every editable text field and text
/// editor in the app, including SwiftUI `TextField` and `TextEditor` (which do
/// not expose a spell-check modifier on macOS).
@MainActor
public final class SpellCheckEnabler: NSObject {
    public static let shared = SpellCheckEnabler()

    private var started = false

    private override init() {
        super.init()
    }

    public func start() {
        guard !started else { return }
        started = true

        // Selector-based observers run on the posting thread (the main thread
        // for AppKit) and avoid sending non-Sendable notifications across
        // actors.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controlDidBeginEditing(_:)),
            name: NSControl.textDidBeginEditingNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidBeginEditing(_:)),
            name: NSText.didBeginEditingNotification,
            object: nil
        )
    }

    @objc private func controlDidBeginEditing(_ note: Notification) {
        guard let control = note.object as? NSControl else { return }
        enable(control: control)
    }

    @objc private func textDidBeginEditing(_ note: Notification) {
        guard let textView = note.object as? NSTextView else { return }
        enable(textView: textView)
    }

    /// Enables spell checking for an `NSTextField`'s field editor.
    public func enable(control: NSControl) {
        guard !(control is NSSecureTextField) else { return }
        guard let editor = control.currentEditor() as? NSTextView else { return }
        enable(textView: editor)
    }

    /// Enables continuous spell checking for a text view.
    public func enable(textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = true
    }
}
#endif
