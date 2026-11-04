#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import TodayFlowCore
import TodayFlowDesign
import TodayFlowMac
import TodayFlowRecognition

@MainActor
private func makeEnvironment() -> AppEnvironment {
    AppEnvironment(
        workItems: InMemoryWorkItemRepository(),
        links: InMemoryLinkRepository(),
        attachments: InMemoryAttachmentRepository(),
        settings: InMemorySettingRepository(),
        keychain: InMemoryKeychainStore(),
        pipeline: .standard
    )
}

struct WindowManagerTests {
    @Test @MainActor
    func show_createsWindowAtCatalogSize() {
        let manager = WindowManager(environment: makeEnvironment())
        #expect(!manager.isOpen(.hierarchy))
        #expect(manager.openCount == 0)
        manager.show(.hierarchy)
        #expect(manager.isOpen(.hierarchy))
        #expect(manager.openCount == 1)
        #expect(manager.window(for: .hierarchy)?.title == "Hierarchy")
        #expect(manager.window(for: .hierarchy)?.contentView?.frame.size == DesignTokens.Window.hierarchy)
    }

    @Test @MainActor
    func show_twice_reusesTheSameWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let first = manager.window(for: .panel)
        manager.show(.panel)
        let second = manager.window(for: .panel)
        #expect(first === second)
        #expect(manager.openCount == 1)
    }

    @Test @MainActor
    func close_removesWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.settings)
        #expect(manager.isOpen(.settings))
        manager.close(.settings)
        #expect(!manager.isOpen(.settings))
        #expect(manager.openCount == 0)
    }

    @Test @MainActor
    func closeAll_closesEveryOpenWindow() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        manager.show(.hierarchy)
        manager.show(.settings)
        #expect(manager.openCount == 3)
        manager.closeAll()
        #expect(manager.openCount == 0)
    }

    @Test @MainActor
    func panelWindowHasMinimumSizeFromDesignTokens() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        #expect(manager.window(for: .panel)?.contentMinSize == DesignTokens.Window.panelMinimum)
    }

    @Test @MainActor
    func panelWindowIsFloatingPanel() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.panel)
        let window = manager.window(for: .panel)
        #expect(window is PanelWindow)
        #expect((window as? PanelWindow)?.isFloatingPanel == true)
        #expect(window?.level == .floating)
    }

    @Test @MainActor
    func slimBarWindowUsesSlimBarSize() {
        let manager = WindowManager(environment: makeEnvironment())
        manager.show(.slimBar)
        let window = manager.window(for: .slimBar)
        #expect(window is PanelWindow)
        #expect(window?.contentView?.frame.size == DesignTokens.Window.slimBar)
        #expect(window?.contentMaxSize == DesignTokens.Window.slimBar)
    }
}
#endif
