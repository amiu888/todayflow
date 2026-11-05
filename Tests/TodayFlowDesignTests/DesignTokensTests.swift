import SwiftUI
import Testing
import TodayFlowDesign

/// driver.md §4 window modes: Panel 360×640 (min 280×420), Slim bar 360×44,
/// menu bar popover 340×480, Detail 720×640.
@Suite("DesignTokens")
struct DesignTokensTests {
    @Test("windowSizesMatchDriverSpec")
    func windowSizesMatchDriverSpec() {
        #expect(DesignTokens.Window.panel == CGSize(width: 360, height: 640))
        #expect(DesignTokens.Window.panelMinimum == CGSize(width: 280, height: 420))
        #expect(DesignTokens.Window.slimBar == CGSize(width: 360, height: 44))
        #expect(DesignTokens.Window.menuBar == CGSize(width: 340, height: 480))
        #expect(DesignTokens.Window.detail == CGSize(width: 720, height: 640))
    }

    @Test("ringGeometryIsThin")
    func ringGeometryIsThin() {
        // Thin marks (data-viz mark spec): a 2.5pt stroke on a ~28pt ring.
        #expect(DesignTokens.Ring.diameter == 28)
        #expect(DesignTokens.Ring.lineWidth == 2.5)
    }
}
