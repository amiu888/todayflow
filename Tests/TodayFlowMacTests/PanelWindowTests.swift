#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import TodayFlowDesign
import TodayFlowMac

struct PanelWindowTests {
    @Test @MainActor
    func panelIsFloatingAndCanBecomeKey() {
        let window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: DesignTokens.Window.panel),
            style: .panel
        )
        #expect(window.isFloatingPanel)
        #expect(window.level == .floating)
        #expect(!window.hidesOnDeactivate)
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(!window.styleMask.contains(.nonactivatingPanel))
        #expect(!window.isMovableByWindowBackground)
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.resizable))
        // A titled window is by definition not borderless. (Do not assert on
        // `.borderless` directly: its rawValue is 0, so `contains` is true
        // for every mask.)
    }

    @Test @MainActor
    func slimBarIsBorderlessAndMovableByBackground() {
        let window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: DesignTokens.Window.slimBar),
            style: .slimBar
        )
        #expect(window.styleMask.contains(.borderless))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.isMovableByWindowBackground)
        #expect(window.canBecomeKey)
        #expect(window.isFloatingPanel)
    }
}
#endif
