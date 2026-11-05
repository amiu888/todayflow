#if canImport(AppKit)
import AppKit
import Testing
import TodayFlowCore
import TodayFlowFeatures
@testable import TodayFlowMac

@Suite("Tray window following")
@MainActor
struct TrayWindowFollowingTests {
    @Test func trackerReportsPanelDelta() {
        var tracker = TrayFollowTracker()
        #expect(tracker.updatePanelOrigin(CGPoint(x: 100, y: 200)) == nil)
        #expect(tracker.updatePanelOrigin(CGPoint(x: 140, y: 180)) == CGSize(width: 40, height: -20))
        #expect(tracker.updatePanelOrigin(CGPoint(x: 140, y: 180)) == nil)
    }

    @Test func programmaticMoveDetectionUsesExpectedOrigin() {
        #expect(TrayFollowTracker.isProgrammaticMove(
            actual: CGPoint(x: 10, y: 20),
            expected: CGPoint(x: 10.4, y: 20.2)
        ))
        #expect(!TrayFollowTracker.isProgrammaticMove(
            actual: CGPoint(x: 30, y: 20),
            expected: CGPoint(x: 10, y: 20)
        ))
    }

    @Test func trayFollowsPanelUntilTheUserMovesIt() async throws {
        _ = NSApplication.shared
        let model = TodayViewModel(
            repository: InMemoryWorkItemRepository(),
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: InMemorySettingRepository(),
            deviceId: "test"
        )
        await model.load()
        let tray = try #require(model.trays.first)

        let panel = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 448),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.orderFront(nil)
        let controller = TrayWindowController(model: model)
        controller.panelWindow = { panel }
        controller.open(trayId: tray.id)
        let trayWindow = try #require(controller.window(trayId: tray.id))

        let start = trayWindow.frame.origin
        panel.setFrameOrigin(NSPoint(x: 160, y: 100))
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(trayWindow.frame.origin.x - (start.x + 60)) < 1)

        trayWindow.setFrameOrigin(
            NSPoint(x: trayWindow.frame.origin.x + 25, y: trayWindow.frame.origin.y)
        )
        try await Task.sleep(for: .milliseconds(150))
        let detached = trayWindow.frame.origin

        panel.setFrameOrigin(NSPoint(x: 220, y: 100))
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(trayWindow.frame.origin.x - detached.x) < 1)

        controller.close(trayId: tray.id)
        panel.close()
    }
}
#endif
