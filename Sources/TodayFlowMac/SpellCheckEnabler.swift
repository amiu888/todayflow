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
        // Check text as soon as a window is in front, not only after the
        // first keystroke: existing notes and summaries get underlined too.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        enable(window: window)
        // SwiftUI builds some text views a moment later (sheets, editors).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak window] in
            MainActor.assumeIsolated {
                guard let window else { return }
                self?.enable(window: window)
            }
        }
    }

    /// Enables checking for the window's field editor (every text field
    /// shares it) and every text view (text editors) in the window.
    public func enable(window: NSWindow) {
        if let editor = window.fieldEditor(true, for: nil) as? NSTextView {
            enable(textView: editor)
        }
        if let content = window.contentView {
            enableTextViews(in: content)
        }
    }

    private func enableTextViews(in view: NSView) {
        if let textView = view as? NSTextView, textView.isEditable {
            enable(textView: textView)
        }
        for subview in view.subviews {
            enableTextViews(in: subview)
        }
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
        guard !textView.isContinuousSpellCheckingEnabled || !textView.isGrammarCheckingEnabled else { return }
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
    }
}
#endif
