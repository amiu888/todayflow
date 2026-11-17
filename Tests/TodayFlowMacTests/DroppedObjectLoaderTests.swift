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

    @Test func providerWhitespaceText_isSkipped() async {
        let provider = NSItemProvider(
            item: "   \n  " as NSString,
            typeIdentifier: UTType.utf8PlainText.identifier
        )
        let objects = await DroppedObjectLoader().load(from: [provider])
        #expect(objects.isEmpty)
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

    @Test func providerJiraURL_keepsTheCardText() async throws {
        let url = try #require(URL(string: "https://acme.atlassian.net/browse/ABC-123"))
        let provider = NSItemProvider(
            item: url as NSURL,
            typeIdentifier: UTType.url.identifier
        )
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("Fix the login timeout".utf8), nil)
            return nil
        }

        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.url == url)
        #expect(objects.first?.text == "Fix the login timeout")
    }

    @Test func providerPlainTextWithJiraURL_loadsURL() async throws {
        let provider = NSItemProvider(
            item: """
            ABC-123 Fix the login timeout
            https://acme.atlassian.net/browse/ABC-123
            """ as NSString,
            typeIdentifier: UTType.utf8PlainText.identifier
        )

        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.url?.absoluteString
            == "https://acme.atlassian.net/browse/ABC-123")
        #expect(objects.first?.text?.contains("Fix the login timeout") == true)
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

    // MARK: Clipboard paste into a task

    private func pngData() throws -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    @Test func clipboardImage_becomesAnImageObject() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setData(try pngData(), forType: .png)

        let objects = DroppedObjectLoader.objectsFromClipboard(pasteboard)
        #expect(objects.count == 1)
        #expect(objects.first?.imageData != nil)
        #expect(DroppedObjectLoader.pasteRoute(
            types: pasteboard.types ?? [], isEditingText: true
        ) == .attach)
    }

    @Test func clipboardImageWithLink_prefersTheImage() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTests-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("https://example.com/cat.png", forType: .URL)
        item.setData(try pngData(), forType: .png)
        #expect(pasteboard.writeObjects([item]))

        #expect(DroppedObjectLoader.objectsFromClipboard(pasteboard).first?.imageData != nil)
        // A drag keeps its existing behavior: the link wins.
        #expect(DroppedObjectLoader.objects(from: pasteboard).first?.url != nil)
    }

    @Test func pasteRoute_keepsTextPastesInTheFocusedField() {
        // Plain text while typing: the field gets it.
        #expect(DroppedObjectLoader.pasteRoute(
            types: [.string], isEditingText: true
        ) == .passThrough)
        // Spreadsheet cells carry text and a picture: still a text paste.
        #expect(DroppedObjectLoader.pasteRoute(
            types: [.string, .tiff], isEditingText: true
        ) == .passThrough)
        // A copied Finder file attaches even while typing.
        #expect(DroppedObjectLoader.pasteRoute(
            types: [.fileURL, .string], isEditingText: true
        ) == .attach)
        // With no field focused, text and links attach too.
        #expect(DroppedObjectLoader.pasteRoute(
            types: [.string], isEditingText: false
        ) == .attach)
        #expect(DroppedObjectLoader.pasteRoute(
            types: [.URL, .string], isEditingText: false
        ) == .attach)
        // Nothing usable.
        #expect(DroppedObjectLoader.pasteRoute(
            types: [], isEditingText: false
        ) == .passThrough)
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

@Suite("DroppedObjectLoader rich text")
@MainActor
struct DroppedObjectLoaderRichTextTests {
    @Test func providerHTML_loadsPlainText() async {
        let html = "<html><body><p>Hello <b>team</b></p></body></html>"
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.html.identifier,
            visibility: .all
        ) { completion in
            completion(Data(html.utf8), nil)
            return nil
        }

        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.text?.contains("Hello") == true)
        #expect(objects.first?.text?.contains("team") == true)
    }

    @Test func pasteboardHTML_readsTeamsChat() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowTeams-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(
            Data("<html><body>Review the deck</body></html>".utf8),
            forType: .html
        )
        item.setData(
            Data(),
            forType: NSPasteboard.PasteboardType("com.microsoft.teams2.message")
        )
        pasteboard.writeObjects([item])

        #expect(DroppedObjectLoader.canRead(pasteboard))
        let objects = DroppedObjectLoader.objects(from: pasteboard)
        #expect(objects.count == 1)
        #expect(objects.first?.text?.contains("Review the deck") == true)
        #expect(objects.first?.sourceApp == "teams")
    }
}

@Suite("DroppedObjectLoader vCard")
@MainActor
struct DroppedObjectLoaderVCardTests {
    @Test func providerVCard_loadsTextAndType() async {
        let vcard = "BEGIN:VCARD\nN:Smith;Jane;;;\nEMAIL:jane@acme.com\nEND:VCARD"
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: "public.vcard",
            visibility: .all
        ) { completion in
            completion(Data(vcard.utf8), nil)
            return nil
        }

        let objects = await DroppedObjectLoader().load(from: [provider])

        #expect(objects.count == 1)
        #expect(objects.first?.text?.contains("BEGIN:VCARD") == true)
        #expect(objects.first?.uti?.identifier == "public.vcard")
    }

    @Test func pasteboardVCard_readsText() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("TodayFlowVCard-\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(
            Data("BEGIN:VCARD\nN:Smith;Jane;;;\nEND:VCARD".utf8),
            forType: NSPasteboard.PasteboardType("public.vcard")
        )
        pasteboard.writeObjects([item])

        let objects = DroppedObjectLoader.objects(from: pasteboard)
        #expect(objects.count == 1)
        #expect(objects.first?.text?.contains("BEGIN:VCARD") == true)
    }
}

// MARK: - Jira cards dragged from Chrome (web custom data only)

@Test @MainActor
func jiraCardWithOnlyChromeCustomDataBecomesAJiraLink() throws {
    func pickle(_ entries: [(String, String)]) -> Data {
        var payload = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { payload.append(contentsOf: $0) } }
        func s16(_ s: String) {
            let units = Array(s.utf16)
            u32(UInt32(units.count))
            for unit in units { withUnsafeBytes(of: unit.littleEndian) { payload.append(contentsOf: $0) } }
            while payload.count % 4 != 0 { payload.append(0) }
        }
        u32(UInt32(entries.count))
        for (type, value) in entries { s16(type); s16(value) }
        var data = Data()
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
        return data + payload
    }
    let json = #"{"issueKey":"ABC-42","summary":"Fix login","baseUrl":"https://acme.atlassian.net"}"#
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    let type = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
    pasteboard.declareTypes([type], owner: nil)
    #expect(pasteboard.setData(pickle([("application/x-jira-card", json)]), forType: type))

    #expect(DroppedObjectLoader.canRead(pasteboard))
    let object = try #require(DroppedObjectLoader.objects(from: pasteboard).first)
    #expect(object.url?.absoluteString == "https://acme.atlassian.net/browse/ABC-42")
    #expect(object.text == "Fix login")

    let recognized = JiraIssueRecognizer().recognize(object)
    #expect(recognized.suggestedTitle == "ABC-42 · Fix login")
}
