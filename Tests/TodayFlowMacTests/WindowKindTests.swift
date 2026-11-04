import Foundation
import Testing
import TodayFlowCore
import TodayFlowDesign
import TodayFlowMac

struct WindowKindTests {
    @Test
    func sizesMatchDesignTokens() {
        #expect(WindowKind.panel.size == DesignTokens.Window.panel)
        #expect(WindowKind.hierarchy.size == DesignTokens.Window.hierarchy)
        #expect(WindowKind.settings.size == DesignTokens.Window.settings)
        #expect(WindowKind.detail(UUIDv7.new()).size == DesignTokens.Window.detail)
    }

    @Test
    func titles() {
        #expect(WindowKind.panel.title == "Today")
        #expect(WindowKind.hierarchy.title == "Hierarchy")
        #expect(WindowKind.settings.title == "Settings")
        #expect(WindowKind.detail(UUIDv7.new()).title == "Task")
    }

    @Test
    func detailWindowsAreDistinctPerItem() {
        let a = UUIDv7.new()
        let b = UUIDv7.new()
        #expect(WindowKind.detail(a) != WindowKind.detail(b))
        #expect(WindowKind.detail(a) == WindowKind.detail(a))
    }
}
