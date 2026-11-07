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
}
