#if canImport(AppKit)
import AppKit
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Opens the AI Writer for a piece of text: from a ✨ button (the caller
/// says how to apply the result) or from Edit ▸ Rewrite with AI… for
/// whatever text box has focus.
@MainActor
public final class AIWriterController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private var window: NSWindow?
    private var model: AIWriterModel?
    public var onOpenSettings: (@MainActor () -> Void)?

    public init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
    }

    /// Opens the writer for `text`; `apply` receives the chosen version.
    public func open(
        text: String,
        fieldName: String,
        applyTitle: String = "Replace",
        near source: NSWindow?,
        apply: @escaping @MainActor (String) -> Void
    ) {
        let model = AIWriterModel(original: text, fieldName: fieldName, applyTitle: applyTitle)
        model.onApply = apply
        model.onClose = { [weak self] in self?.close() }
        if let openSettings = onOpenSettings {
            model.onOpenSettings = { [weak self] in
                self?.close()
                openSettings()
            }
        }
        self.model = model

        let window = self.window ?? makeWindow()
        window.contentViewController = NSHostingController(rootView: AIWriterView(model: model))
        WindowSizeMemory.makeResizable(window, name: "aiWriter", minimum: NSSize(width: 560, height: 480))
        WindowPlacement.besideMainWindow(window, main: source)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        Task { @MainActor [weak model, environment] in
            let rewriter = await environment.ai?.rewriter()
            model?.rewriter = rewriter
            model?.isResolvingAI = false
        }
    }

    /// Edit ▸ Rewrite with AI…: the selection, or all the text, of the text
    /// box that has focus. Returns false when no text box has focus.
    @discardableResult
    public func rewriteFocusedText() -> Bool {
        guard let source = NSApp.keyWindow, source !== window,
              let textView = source.firstResponder as? NSTextView,
              textView.isEditable
        else { return false }
        let selection = textView.selectedRange()
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        let range = selection.length > 0 ? selection : whole
        let text = (textView.string as NSString).substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let before = textView.string

        open(text: text, fieldName: selection.length > 0 ? "Selected text" : "This text box", near: source) {
            [weak textView, weak source] rewritten in
            guard let source, let textView else { return Self.copyInstead(rewritten) }
            source.makeKeyAndOrderFront(nil)
            // Replace only if the box is still focused and unchanged.
            guard source.firstResponder === textView, textView.string == before,
                  textView.shouldChangeText(in: range, replacementString: rewritten)
            else { return Self.copyInstead(rewritten) }
            textView.replaceCharacters(in: range, with: rewritten)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location, length: (rewritten as NSString).length))
        }
        return true
    }

    private static func copyInstead(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let alert = NSAlert()
        alert.messageText = "The text box changed or closed"
        alert.informativeText = "The rewrite was copied instead. Click into the text box and press ⌘V."
        alert.runModal()
    }

    public func close() {
        window?.orderOut(nil)
        window?.contentViewController = nil
        model = nil
    }

    public func windowWillClose(_ notification: Notification) {
        model = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Writer"
        // Task windows and the panel float; keep the writer above them.
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        return window
    }
}
#endif
