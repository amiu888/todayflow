#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import TodayFlowMac
import TodayFlowRecognition

/// Drop conversion from AppKit providers and pasteboards (FR-01/FR-06).
@MainActor
struct DroppedObjectLoaderTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func providerFileURL_loadsFileMetadata() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let provider = try #require(NSItemProvider(contentsOf: file))
        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.fileURL?.standardizedFileURL == file.standardizedFileURL)
        #expect(objects.first?.isDirectory == false)
        #expect(objects.first?.fileSize == 5)
        #expect(objects.first?.uti?.conforms(to: .plainText) == true)
    }

    @Test func providerText_loadsPlainText() async throws {
        let provider = NSItemProvider(
            item: "Call Bob tomorrow" as NSString,
            typeIdentifier: UTType.utf8PlainText.identifier
        )
        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.text == "Call Bob tomorrow")
        #expect(objects.first?.uti?.conforms(to: .plainText) == true)
    }

    @Test func providerWebURL_loadsURL() async throws {
        let url = try #require(URL(string: "https://example.com/article"))
        let provider = NSItemProvider(
            item: url as NSURL,
            typeIdentifier: UTType.url.identifier
        )
        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.url == url)
        #expect(objects.first?.fileURL == nil)
    }

    @Test func pasteboardFileURL_readsFile() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        let file = URL(fileURLWithPath: "/tmp/todayflow-report.pdf")
        #expect(pasteboard.writeObjects([file as NSURL]))

        let objects = DroppedObjectLoader.objects(from: pasteboard)
        #expect(objects.count == 1)
        #expect(objects.first?.fileURL?.path == file.path)
        #expect(objects.first?.uti?.conforms(to: .pdf) == true)
        #expect(DroppedObjectLoader.canRead(pasteboard))
    }

    @Test func pasteboardText_readsText() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("A note from the clipboard", forType: .string)

        let objects = DroppedObjectLoader.objects(from: pasteboard)
        #expect(objects.count == 1)
        #expect(objects.first?.text == "A note from the clipboard")
    }

    @Test func emptyPasteboard_isNotReadable() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        #expect(!DroppedObjectLoader.canRead(pasteboard))
        #expect(DroppedObjectLoader.objects(from: pasteboard).isEmpty)
    }

    @Test func urlData_acceptsPlainURLString() throws {
        let url = try #require(URL(string: "https://example.com/path?q=1"))
        let data = Data(url.absoluteString.utf8)
        #expect(DroppedObjectLoader.url(from: data) == url)
    }
}
#endif
