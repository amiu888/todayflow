#if canImport(AppKit)
import CoreGraphics
import Testing
@testable import TodayFlowMac

struct WindowDockGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func snapsToTheLeftScreenEdge() {
        let frame = CGRect(x: 5, y: 200, width: 360, height: 640)
        let result = WindowDockGeometry.snapped(frame, within: screen)
        #expect(result.origin.x == 0)
        #expect(result.origin.y == 200)
    }

    @Test func snapsToTheRightScreenEdge() {
        let frame = CGRect(x: 1440 - 360 - 6, y: 200, width: 360, height: 640)
        let result = WindowDockGeometry.snapped(frame, within: screen)
        #expect(result.maxX == screen.maxX)
    }

    @Test func snapsBelowTheMenuBar() {
        let frame = CGRect(x: 500, y: 900 - 640 - 8, width: 360, height: 640)
        let result = WindowDockGeometry.snapped(frame, within: screen)
        #expect(result.maxY == screen.maxY)
    }

    @Test func snapsBesideAnotherWindow() {
        let neighbour = CGRect(x: 100, y: 100, width: 400, height: 500)
        let frame = CGRect(x: 506, y: 120, width: 360, height: 400)

        let result = WindowDockGeometry.snapped(frame, within: screen, others: [neighbour])

        #expect(result.minX == neighbour.maxX)
    }

    @Test func snapsAboveAnotherWindow() {
        let neighbour = CGRect(x: 300, y: 100, width: 400, height: 500)
        let frame = CGRect(x: 320, y: 606, width: 360, height: 300)

        let result = WindowDockGeometry.snapped(frame, within: screen, others: [neighbour])

        #expect(result.minY == neighbour.maxY)
    }

    @Test func leavesAFreeFloatingFrameAlone() {
        let frame = CGRect(x: 500, y: 300, width: 360, height: 400)
        let result = WindowDockGeometry.snapped(frame, within: screen)
        #expect(result == frame)
    }
}
#endif

struct AppDockGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1600)
    private let panel = CGSize(width: 360, height: 448)
    private let target = CGRect(x: 700, y: 500, width: 800, height: 500)

    @Test func attachesToTheLeftByDefault() {
        let result = AppDockGeometry.dockedFrame(
            panelSize: panel,
            target: target,
            edge: .left,
            screen: screen
        )
        #expect(result.maxX == target.minX - 8)
        #expect(result.maxY == target.maxY)
    }

    @Test func attachesToTheRight() {
        let result = AppDockGeometry.dockedFrame(
            panelSize: panel,
            target: target,
            edge: .right,
            screen: screen
        )
        #expect(result.minX == target.maxX + 8)
        #expect(result.maxY == target.maxY)
    }

    @Test func attachesAboveAndBelow() {
        let top = AppDockGeometry.dockedFrame(
            panelSize: panel,
            target: target,
            edge: .top,
            screen: screen
        )
        let bottom = AppDockGeometry.dockedFrame(
            panelSize: panel,
            target: target,
            edge: .bottom,
            screen: screen
        )
        #expect(top.minY == target.maxY + 8)
        #expect(bottom.maxY == target.minY - 8)
        #expect(top.midX == target.midX)
    }

    @Test func clampsToTheScreen() {
        let edgeTarget = CGRect(x: 0, y: 0, width: 300, height: 200)
        let result = AppDockGeometry.dockedFrame(
            panelSize: panel,
            target: edgeTarget,
            edge: .left,
            screen: screen
        )
        #expect(result.minX == screen.minX)
        #expect(result.minY >= screen.minY)
    }
}

struct TrayWindowLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let panel = CGRect(x: 780, y: 300, width: 360, height: 448)
    private let traySize = CGSize(width: 420, height: 520)

    @Test func firstTrayAttachesToThePanelRightEdge() {
        let frame = TrayWindowLayout.frame(
            size: traySize,
            panel: panel,
            existing: [],
            screen: screen
        )
        #expect(frame.minX == panel.maxX + 8)
        #expect(frame.maxY == panel.maxY)
    }

    @Test func nextTrayAttachesToTheLastTray() {
        let leftPanel = CGRect(x: 100, y: 300, width: 360, height: 448)
        let first = TrayWindowLayout.frame(
            size: traySize,
            panel: leftPanel,
            existing: [],
            screen: screen
        )
        let second = TrayWindowLayout.frame(
            size: traySize,
            panel: leftPanel,
            existing: [first],
            screen: screen
        )
        #expect(second.minX == first.maxX + 8)
        #expect(second.maxY == first.maxY)
    }

    @Test func fallsBackBelowWhenTheRowIsFull() {
        let rightPanel = CGRect(x: 780, y: 700, width: 360, height: 300)
        let stackedSize = CGSize(width: 420, height: 250)
        let first = TrayWindowLayout.frame(
            size: stackedSize,
            panel: rightPanel,
            existing: [],
            screen: screen
        )
        let second = TrayWindowLayout.frame(
            size: stackedSize,
            panel: rightPanel,
            existing: [first],
            screen: screen
        )
        let third = TrayWindowLayout.frame(
            size: stackedSize,
            panel: rightPanel,
            existing: [first, second],
            screen: screen
        )
        #expect(third.maxX <= screen.maxX)
        #expect(third.maxY <= second.minY)
    }
}

struct WindowOpeningLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let detailSize = CGSize(width: 720, height: 640)

    @Test func opensToTheRightWhenItFits() throws {
        let panel = CGRect(x: 100, y: 300, width: 360, height: 448)
        let frame = try #require(WindowOpeningLayout.frame(
            size: detailSize,
            panel: panel,
            screen: screen
        ))
        #expect(frame.minX == panel.maxX + 8)
        #expect(frame.maxY == panel.maxY)
        #expect(frame.maxX <= screen.maxX)
    }

    @Test func opensToTheLeftWhenTheRightSideIsFull() throws {
        let panel = CGRect(x: 1100, y: 300, width: 360, height: 448)
        let frame = try #require(WindowOpeningLayout.frame(
            size: detailSize,
            panel: panel,
            screen: screen
        ))
        #expect(frame.maxX == panel.minX - 8)
        #expect(frame.maxY == panel.maxY)
        #expect(frame.minX >= screen.minX)
    }

    @Test func staysOnScreenWhenNeitherSideFits() throws {
        let panel = CGRect(x: 600, y: 300, width: 360, height: 448)
        let frame = try #require(WindowOpeningLayout.frame(
            size: CGSize(width: 1000, height: 640),
            panel: panel,
            screen: screen
        ))
        #expect(frame.minX >= screen.minX)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.maxY <= screen.maxY)
    }

    @Test func clampsVerticallyToTheVisibleScreen() throws {
        let panel = CGRect(x: 100, y: 50, width: 360, height: 448)
        let frame = try #require(WindowOpeningLayout.frame(
            size: detailSize,
            panel: panel,
            screen: screen
        ))
        #expect(frame.minY >= screen.minY)
        #expect(frame.maxY <= screen.maxY)
    }

    @Test func withoutAPanelTheCallerFallsBackToCenter() {
        #expect(WindowOpeningLayout.frame(
            size: detailSize,
            panel: nil,
            screen: screen
        ) == nil)
    }
}
