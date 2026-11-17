#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import TodayFlowFeatures

@MainActor
struct PasteCatcherTests {
    private func find(_ view: NSView) -> PasteCatcher.MonitorView? {
        if let v = view as? PasteCatcher.MonitorView { return v }
        for sub in view.subviews { if let f = find(sub) { return f } }
        return nil
    }

    @Test func zeroSizedCatcherInBackground_isInstalledInTheWindow() {
        let root = Text("Task")
            .frame(width: 200, height: 100)
            .background {
                PasteCatcher(onPaste: { _ in true })
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        let host = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let monitor = find(host)
        #expect(monitor != nil)
        #expect(monitor?.window === window)
    }

    @Test func pasteShortcut_isPlainCommandV() {
        #expect(PasteCatcher.isPasteShortcut(characters: "v", modifiers: [.command]))
        #expect(PasteCatcher.isPasteShortcut(characters: "V", modifiers: [.command, .capsLock]))
        #expect(!PasteCatcher.isPasteShortcut(characters: "v", modifiers: [.command, .shift]))
        #expect(!PasteCatcher.isPasteShortcut(characters: "v", modifiers: []))
        #expect(!PasteCatcher.isPasteShortcut(characters: "c", modifiers: [.command]))
    }
}
#endif
