#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import TodayFlowMac

struct StatusItemIconTests {
    @Test @MainActor
    func imageIsTemplateAtMenuBarSize() {
        let image = StatusItemIcon.image(fraction: 0.5)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }

    @Test @MainActor
    func drawingProducesPixels() {
        let image = StatusItemIcon.image(fraction: 0.75)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 18,
            pixelsHigh: 18,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 18 * 4,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()

        var nonTransparent = false
        for x in 0..<18 {
            for y in 0..<18 {
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0 {
                    nonTransparent = true
                    break
                }
            }
            if nonTransparent { break }
        }
        #expect(nonTransparent, "the ring must draw visible pixels")
    }
}
#endif
