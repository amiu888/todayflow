import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowSync

/// Two Macs against a real server. Runs only when told where one is:
///
///     TODAYFLOW_E2E_URL=http://127.0.0.1:18787 TODAYFLOW_E2E_CODE=<pairing code> swift test --filter LiveServer
struct LiveServerTests {
    static let url = ProcessInfo.processInfo.environment["TODAYFLOW_E2E_URL"]
    static let code = ProcessInfo.processInfo.environment["TODAYFLOW_E2E_CODE"]

    struct LiveMac {
        let queue: DatabaseQueue
        let items: GRDBWorkItemRepository
        let runner: SyncRunner

        init(name: String) async throws {
            let base = try SyncClient.serverURL(from: LiveServerTests.url!)
            let paired = try await SyncClient(baseURL: base, token: nil).pair(code: LiveServerTests.code!, deviceName: name)
            queue = try TodayFlowDatabase.makeInMemory()
            items = GRDBWorkItemRepository(queue: queue)
            runner = SyncRunner(store: SyncStore(queue: queue), client: SyncClient(baseURL: base, token: paired.token))
        }
    }

    @Test(.enabled(if: url != nil && code != nil))
    func twoMacsSyncThroughTheServer() async throws {
        let a = try await LiveMac(name: "E2E Mac A")
        let b = try await LiveMac(name: "E2E Mac B")

        let item = WorkItem(title: "Live sync \(UUID().uuidString.prefix(6))", descriptionMd: "Notes ✓ ünïcode", tags: ["e2e"])
        try await a.items.save(item)
        let sent = try await a.runner.run()
        #expect(sent.sent > 0)
        _ = try await b.runner.run()
        let copy = try #require(await b.items.item(item.id))
        #expect(copy.title == item.title)
        #expect(copy.descriptionMd == "Notes ✓ ünïcode")
        #expect(copy.tags == ["e2e"])

        var edited = copy
        edited.title += " (edited on B)"
        edited.priority = .urgent
        try await b.items.save(edited)
        _ = try await b.runner.run()
        _ = try await a.runner.run()
        let back = try #require(await a.items.item(item.id))
        #expect(back.title == edited.title)
        #expect(back.priority == .urgent)

        // Nothing echoes: a second round sends and receives nothing.
        let quietA = try await a.runner.run()
        let quietB = try await b.runner.run()
        #expect(quietA == .init())
        #expect(quietB == .init())

        // A wrong token is "signed out".
        let bad = SyncClient(baseURL: try SyncClient.serverURL(from: Self.url!), token: "nope")
        await #expect(throws: SyncError.signedOut) { try await bad.pull(since: 0, limit: 1) }
    }
}

/// First sync of a copy of a real database: every synced row arrives on an
/// empty Mac unchanged. `TODAYFLOW_E2E_DB=<copy of todayflow.sqlite>` plus the two above.
struct LiveFirstSyncTests {
    static let db = ProcessInfo.processInfo.environment["TODAYFLOW_E2E_DB"]

    @Test(.enabled(if: LiveServerTests.url != nil && LiveServerTests.code != nil && db != nil))
    func realDataCopy_arrivesWhole() async throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("tf-real-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: Self.db!), to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let source = try TodayFlowDatabase.make(at: copy)
        let base = try SyncClient.serverURL(from: LiveServerTests.url!)
        let filesB = FileManager.default.temporaryDirectory.appendingPathComponent("tf-real-files-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: filesB) }
        func runner(_ queue: DatabaseQueue, _ name: String, files: URL) async throws -> SyncRunner {
            let paired = try await SyncClient(baseURL: base, token: nil).pair(code: LiveServerTests.code!, deviceName: name)
            return SyncRunner(store: SyncStore(queue: queue), client: SyncClient(baseURL: base, token: paired.token), filesDirectory: files)
        }
        let store = SyncStore(queue: source)
        try await store.markAllPending()
        let first = try await runner(source, "Real copy", files: FileManager.default.temporaryDirectory).run()
        #expect(try await store.pendingCount() == 0)

        let empty = try TodayFlowDatabase.makeInMemory()
        var other = try await runner(empty, "Empty Mac", files: filesB)
        other.useOriginalPaths = false // act like a second Mac
        let received = try await other.run()
        print("first sync sent \(first.sent) rows and \(first.filesUploaded) files; empty Mac received \(received.received) rows and \(received.filesDownloaded) files; file errors \(first.fileErrors)/\(received.fileErrors)")

        // Every file that exists on the source Mac arrives with the same bytes.
        let sourceFiles = try await SyncStore(queue: source).attachmentsWithBlob()
        let gotFiles = try await SyncStore(queue: empty).attachmentsWithBlob()
        var checked = 0
        for file in sourceFiles {
            let mine = try #require(file.localFile)
            let theirs = try #require(gotFiles.first { $0.id == file.id }?.localCopyPath, "\(file.displayName) not downloaded")
            #expect(try Data(contentsOf: mine) == Data(contentsOf: URL(fileURLWithPath: theirs)))
            #expect(theirs.hasPrefix(filesB.path))
            checked += 1
        }
        print("files compared byte for byte: \(checked)")

        for table in SyncTables.all {
            let columns = try await source.read { try $0.columns(in: table.name).map(\.name) }
                .filter { !table.localOnly.contains($0) }
            let list = columns.map { "\"\($0)\"" }.joined(separator: ", ")
            let order = table.key.joined(separator: ", ")
            let sql = "SELECT \(list) FROM \"\(table.name)\" ORDER BY \(order)"
            let want = try await source.read { try Row.fetchAll($0, sql: sql).map { $0.databaseValues.map(\.description) } }
            let got = try await empty.read { try Row.fetchAll($0, sql: sql).map { $0.databaseValues.map(\.description) } }
            // The test user may already hold rows from other live tests.
            let missing = Set(want).subtracting(got)
            #expect(missing.isEmpty, "\(table.name): \(missing.count) of \(want.count) rows missing or different")
            print("\(table.name): \(want.count) rows, all arrived: \(missing.isEmpty)")
        }
    }
}

/// A big file through a real server: uploaded streaming, not downloaded in a
/// round, fetched when opened.
struct LiveBigFileTests {
    @Test(.enabled(if: LiveServerTests.url != nil && LiveServerTests.code != nil))
    func bigFile_streamsUpAndDownloadsWhenOpened() async throws {
        let base = try SyncClient.serverURL(from: LiveServerTests.url!)
        func mac(_ name: String) async throws -> (DatabaseQueue, SyncRunner, URL) {
            let paired = try await SyncClient(baseURL: base, token: nil).pair(code: LiveServerTests.code!, deviceName: name)
            let queue = try TodayFlowDatabase.makeInMemory()
            let files = FileManager.default.temporaryDirectory.appendingPathComponent("tf-live-\(UUID().uuidString)")
            var runner = SyncRunner(store: SyncStore(queue: queue), client: SyncClient(baseURL: base, token: paired.token), filesDirectory: files)
            runner.useOriginalPaths = false
            return (queue, runner, files)
        }
        let (qa, ra, _) = try await mac("Big A")
        let (qb, rb, filesB) = try await mac("Big B")
        defer { try? FileManager.default.removeItem(at: filesB) }

        let task = WorkItem(title: "Big video \(UUID().uuidString.prefix(4))")
        try await GRDBWorkItemRepository(queue: qa).save(task)
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("tf-video-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: video) }
        var bytes = Data(count: 40 * 1_048_576)
        bytes.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        try bytes.write(to: video)
        try await GRDBAttachmentRepository(queue: qa).save(Attachment(itemId: task.id, kind: .file, displayName: "video.mov", reference: video.path))

        #expect(try await ra.run().filesUploaded == 1)
        #expect(try await rb.run().filesDownloaded == 0)
        let onB = try #require(await GRDBAttachmentRepository(queue: qb).attachments(for: task.id).first)
        let fetched = try #require(try await rb.fetchFile(attachmentId: onB.id.description))
        #expect(try Data(contentsOf: fetched) == bytes)
        print("40 MB file streamed up and fetched on demand")
    }
}
