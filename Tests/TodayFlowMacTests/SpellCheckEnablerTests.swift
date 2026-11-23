import AppKit
import Testing
import TodayFlowMac

@MainActor
struct SpellCheckEnablerTests {
    @Test func enablesContinuousSpellChecking() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 30))
        SpellCheckEnabler.shared.enable(textView: textView)
        #expect(textView.isContinuousSpellCheckingEnabled)
    }

    @Test func enablesEveryTextBoxInAWindowBeforeTyping() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let container = NSView(frame: window.contentRect(forFrameRect: window.frame))
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        editor.isContinuousSpellCheckingEnabled = false
        let readOnly = NSTextView(frame: NSRect(x: 0, y: 100, width: 200, height: 40))
        readOnly.isEditable = false
        readOnly.isContinuousSpellCheckingEnabled = false
        container.addSubview(editor)
        container.addSubview(readOnly)
        window.contentView = container

        SpellCheckEnabler.shared.enable(window: window)

        #expect(editor.isContinuousSpellCheckingEnabled)
        #expect(editor.isGrammarCheckingEnabled)
        #expect(!readOnly.isContinuousSpellCheckingEnabled)
        #expect((window.fieldEditor(true, for: nil) as? NSTextView)?.isContinuousSpellCheckingEnabled == true)
    }
}
