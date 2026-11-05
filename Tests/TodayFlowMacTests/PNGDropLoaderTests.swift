#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
import TodayFlowMac

/// Regression coverage for the Finder → `NSItemProvider` conversion of a PNG.
@MainActor
struct PNGDropLoaderTests {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @Test func pngFileProvider_loadsAsImageFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowPNGDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = root.appendingPathComponent("screen.png")
        try Self.png.write(to: image)

        let provider = try #require(NSItemProvider(contentsOf: image))
        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.fileURL?.standardizedFileURL == image.standardizedFileURL)
        #expect(objects.first?.isDirectory == false)
        #expect(objects.first?.uti?.conforms(to: .image) == true)
    }

    /// Finder hands file URLs over as `NSURL`; make sure that form works too,
    /// not just the `NSItemProvider(contentsOf:)` convenience.
    @Test func pngFileURLAsNSURL_loadsAsImageFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowPNGDrop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = root.appendingPathComponent("screen.png")
        try Self.png.write(to: image)

        let provider = NSItemProvider(
            item: image as NSURL,
            typeIdentifier: UTType.fileURL.identifier
        )
        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.fileURL?.standardizedFileURL == image.standardizedFileURL)
        #expect(objects.first?.uti?.conforms(to: .image) == true)
    }
}
#endif
