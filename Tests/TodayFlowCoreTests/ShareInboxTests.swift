import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Share inbox")
struct ShareInboxTests {
    private func makeInbox() throws -> (ShareInbox, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("inbox-\(UUID().uuidString)", isDirectory: true)
        return (ShareInbox(directory: root.appendingPathComponent("Inbox")), root)
    }

    @Test func addedItemsComeBackWithTheirFiles() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("photo.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: source)

        let saved = try inbox.add(
            ShareInboxItem(title: "Whiteboard", priority: .high, due: .tomorrow, urls: [URL(string: "https://example.com")!]),
            copying: [source, source]
        )
        #expect(saved.files == ["photo.png", "photo 2.png"])

        let pending = inbox.pending()
        #expect(pending == [saved])
        #expect(inbox.fileURLs(for: saved).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        inbox.remove(saved.id)
        #expect(inbox.pending().isEmpty)
    }

    @Test func halfWrittenFoldersAreSkippedAndOrderIsOldestFirst() throws {
        let (inbox, root) = try makeInbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let later = try inbox.add(ShareInboxItem(createdAt: Date(timeIntervalSince1970: 200), title: "B"))
        let earlier = try inbox.add(ShareInboxItem(createdAt: Date(timeIntervalSince1970: 100), title: "A"))
        try FileManager.default.createDirectory(at: inbox.folder(for: UUID()), withIntermediateDirectories: true)
        #expect(inbox.pending().map(\.id) == [earlier.id, later.id])
    }

    @Test func missingInboxIsEmpty() {
        let inbox = ShareInbox(directory: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        #expect(inbox.pending().isEmpty)
    }
}
