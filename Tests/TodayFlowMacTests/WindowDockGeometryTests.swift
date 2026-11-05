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
