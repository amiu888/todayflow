import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowSync

/// The server's rules (Server/Sources/TodayFlowServerKit/Store.swift) in
/// memory: newest `changedAt` wins, one global sequence, a pull leaves out
/// the caller's own changes.
actor FakeServer {
    struct Stored { var change: SyncChange; var seq: Int64; var device: String }
    private var records: [String: Stored] = [:]
    private var seq: Int64 = 0
    var pageSize = 1000

    /// Like the server: a change dated over 10 minutes ahead fails the push.
    struct FutureChange: Error {}

    func push(_ changes: [SyncChange], device: String) throws -> [SyncClient.PushResult] {
        let limit = SqlTimestamp.encode(Date().addingTimeInterval(600))
        if changes.contains(where: { $0.changedAt > limit }) { throw FutureChange() }
        return changes.map { change in
            let key = change.entity + "/" + change.id
            if let existing = records[key], existing.change.changedAt > change.changedAt {
                return .init(entity: change.entity, id: change.id, status: "stale", current: existing.change)
            }
            seq += 1
            var stored = change
            if change.op == "delete" { stored.data = records[key]?.change.data }
            records[key] = Stored(change: stored, seq: seq, device: device)
            return .init(entity: change.entity, id: change.id, status: "accepted", current: nil)
        }
    }

    func pull(since: Int64, limit: Int, device: String) -> SyncClient.PullPage {
        let newer = records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
        let page = Array(newer.prefix(min(limit, pageSize)))
        return .init(
            changes: page.filter { $0.device != device }.map(\.change),
            next: page.last?.seq ?? since,
            more: newer.count > page.count
        )
    }

    func data(_ entity: String, _ id: String) -> SyncRow? { records[entity + "/" + id]?.change.data }

    private(set) var blobs: [String: Data] = [:]
    private(set) var uploads = 0
    func hasBlob(_ sha: String) -> Bool { blobs[sha] != nil }
    func putBlob(_ data: Data, _ sha: String) { uploads += 1; blobs[sha] = data }
    func getBlob(_ sha: String) -> Data? { blobs[sha] }
    func count() -> Int { records.count }
}

struct FakeTransport: SyncTransport {
    let server: FakeServer
    let device: String
    func pull(since: Int64, limit: Int) async throws -> SyncClient.PullPage {
        await server.pull(since: since, limit: limit, device: device)
    }
    func push(_ changes: [SyncChange]) async throws -> [SyncClient.PushResult] {
        try await server.push(changes, device: device)
    }
    func hasBlob(_ sha256: String) async throws -> Bool { await server.hasBlob(sha256) }
    func putBlob(file: URL, sha256: String) async throws { await server.putBlob(try Data(contentsOf: file), sha256) }
    func getBlob(_ sha256: String, to destination: URL) async throws -> Bool {
        guard let data = await server.getBlob(sha256) else { return false }
        try data.write(to: destination)
        return true
    }
}

/// One Mac: its own database and repositories.
struct Mac {
    let queue: DatabaseQueue
    let items: GRDBWorkItemRepository
    let contacts: GRDBContactRepository
    let store: SyncStore
    var runner: SyncRunner

    let files: URL

    init(_ name: String, server: FakeServer) throws {
        queue = try TodayFlowDatabase.makeInMemory()
        items = GRDBWorkItemRepository(queue: queue)
        contacts = GRDBContactRepository(queue: queue)
        store = SyncStore(queue: queue)
        files = FileManager.default.temporaryDirectory.appendingPathComponent("tf-files-\(UUID().uuidString)")
        runner = SyncRunner(store: store, client: FakeTransport(server: server, device: name), filesDirectory: files)
    }

    @discardableResult
    func sync() async throws -> SyncRunner.Report { try await runner.run() }

    func title(_ id: UUIDv7) async -> String? { await items.item(id)?.title }
}

struct ServerSyncTests {
    @Test func everyWriteIsRecorded_andAppliedChangesAreNot() async throws {
        let server = FakeServer()
        let mac = try Mac("A", server: server)
        let item = WorkItem(title: "Write report")
        try await mac.items.save(item)
        let pending = try await mac.store.pendingChanges()
        #expect(pending.contains { $0.entity == "work_item" && $0.id == item.id.description && $0.op == "upsert" })

        try await mac.sync()
        #expect(try await mac.store.pendingCount() == 0)

        // A change from another Mac is applied without being recorded again.
        try await mac.store.apply([SyncChange(
            entity: "work_item", id: item.id.description, op: "upsert",
            changedAt: "2999-01-01T00:00:00.000Z", data: ["id": .string(item.id.description), "title": .string("Renamed")]
        )])
        #expect(await mac.title(item.id) == "Renamed")
        #expect(try await mac.store.pendingCount() == 0)
    }

    @Test func twoMacsConverge_createEditDelete() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)

        let item = WorkItem(title: "Plan trip", descriptionMd: "Book flights", tags: ["travel"])
        try await a.items.save(item)
        try await a.sync()
        try await b.sync()
        let copy = try #require(await b.items.item(item.id))
        #expect(copy.title == "Plan trip")
        #expect(copy.descriptionMd == "Book flights")
        #expect(copy.tags == ["travel"])

        var edited = copy
        edited.title = "Plan trip to Lisbon"
        edited.updatedAt = .now
        try await b.items.save(edited)
        try await b.sync()
        try await a.sync()
        #expect(await a.title(item.id) == "Plan trip to Lisbon")

        // A hard delete travels as a delete.
        try await a.queue.write { db in
            try db.execute(sql: "DELETE FROM work_item WHERE id = ?", arguments: [item.id.description])
        }
        try await a.sync()
        try await b.sync()
        #expect(await b.items.item(item.id) == nil)
        #expect(try await a.store.pendingCount() == 0)
        #expect(try await b.store.pendingCount() == 0)
    }

    @Test func conflictingEdits_newestWins_onBothMacs() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let item = WorkItem(title: "Original")
        try await a.items.save(item)
        try await a.sync()
        try await b.sync()

        // Both edit offline; B edits later.
        try await a.items.save(WorkItem(id: item.id, title: "From A"))
        try await Task.sleep(for: .milliseconds(5))
        try await b.items.save(WorkItem(id: item.id, title: "From B"))

        try await b.sync()
        try await a.sync() // A's older edit is skipped on pull, then refused on push
        try await b.sync()
        #expect(await a.title(item.id) == "From B")
        #expect(await b.title(item.id) == "From B")
        #expect(try await a.store.pendingCount() == 0)
    }

    @Test func offlineQueue_andPagedPull() async throws {
        let server = FakeServer()
        await server.setPageSize(7)
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        for index in 0..<450 {
            try await a.items.save(WorkItem(title: "Task \(index)"))
        }
        let report = try await a.sync()
        #expect(report.sent >= 450) // plus activity rows
        try await b.sync()
        let titles = Set(await b.items.allItems().map(\.title))
        #expect(titles.count == 450)
    }

    @Test func firstSync_sendsExistingRows_andMergesTwoMacs() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let fromA = WorkItem(title: "Made on A before pairing")
        let fromB = WorkItem(title: "Made on B before pairing")
        try await a.items.save(fromA)
        try await b.items.save(fromB)
        // Pretend the rows were there before change tracking existed.
        for mac in [a, b] {
            try await mac.queue.write { try $0.execute(sql: "DELETE FROM sync_change") }
            try await mac.store.markAllPending()
        }
        try await a.sync()
        try await b.sync()
        try await a.sync()
        #expect(await a.title(fromB.id) == fromB.title)
        #expect(await b.title(fromA.id) == fromA.title)
    }

    @Test func rowsStampedInTheFuture_areSentDatedNow() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let later = Date().addingTimeInterval(20 * 24 * 3600)
        let item = WorkItem(title: "Imported with a future time", createdAt: later, updatedAt: later)
        try await a.items.save(item)
        // First sync after pairing: existing rows dated by updated_at.
        try await a.queue.write { try $0.execute(sql: "DELETE FROM sync_change") }
        try await a.store.markAllPending()
        #expect(try await a.store.pendingChanges().allSatisfy { $0.changedAt <= SqlTimestamp.encode(Date()) })
        // A change already queued with a future date (from an older build).
        try await a.queue.write {
            try $0.execute(sql: "UPDATE sync_change SET changed_at = '2099-01-01T00:00:00.000Z'")
        }
        try await a.sync()
        #expect(try await a.store.pendingCount() == 0)
        try await b.sync()
        #expect(await b.title(item.id) == "Imported with a future time")
    }

    @Test func childrenAndCompositeKeys_sync() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let task = WorkItem(title: "Call Ana")
        try await a.items.save(task)
        let contact = Contact(firstName: "Ana", lastName: "Silva")
        try await a.contacts.save(contact)
        try await a.contacts.addContact(contact.id, toTask: task.id)
        try await a.sync()
        try await b.sync()
        #expect(await b.contacts.contacts(forTask: task.id).map(\.firstName) == ["Ana"])

        try await a.contacts.removeContact(contact.id, fromTask: task.id)
        try await a.sync()
        try await b.sync()
        #expect(await b.contacts.contacts(forTask: task.id).isEmpty)
    }

    @Test func attachmentBookmarks_stayOnTheirMac() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let task = WorkItem(title: "Read contract")
        try await a.items.save(task)
        let attachments = GRDBAttachmentRepository(queue: a.queue)
        try await attachments.save(Attachment(
            itemId: task.id, kind: .file, displayName: "contract.pdf",
            reference: "/Users/me/contract.pdf", bookmark: Data([1, 2, 3]), localCopyPath: "/private/copy.pdf"
        ))
        try await a.sync()
        #expect(await server.count() > 0)
        #expect(try await a.store.pendingCount() == 0)
        let attachmentId = try #require(await attachments.attachments(for: task.id).first?.id)
        let data = try #require(await server.data("attachment", attachmentId.description))
        #expect(data["bookmark"] == nil)
        #expect(data["local_copy_path"] == nil)
        #expect(data["display_name"] == .string("contract.pdf"))
    }

    @Test func serverAddress_rules() throws {
        #expect(try SyncClient.serverURL(from: "nas.local:8787").absoluteString == "http://nas.local:8787")
        #expect(try SyncClient.serverURL(from: " http://192.168.1.20:8787/ ").absoluteString == "http://192.168.1.20:8787")
        #expect(try SyncClient.serverURL(from: "https://nas.tail1234.ts.net").scheme == "https")
        #expect(throws: SyncError.self) { try SyncClient.serverURL(from: "http://example.com:8787") }
        #expect(throws: SyncError.self) { try SyncClient.serverURL(from: "") }
    }
}

extension FakeServer {
    func setPageSize(_ size: Int) { pageSize = size }
}

struct FileSyncTests {
    func write(_ text: String, named name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func pastedImage_arrivesOnTheOtherMac_withItsBytesAndExtension() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let task = WorkItem(title: "Screenshot of the bug")
        try await a.items.save(task)
        let copy = try write("PNG bytes", named: "1234-Pasted image.png")
        let attachments = GRDBAttachmentRepository(queue: a.queue)
        try await attachments.save(Attachment(
            itemId: task.id, kind: .image, displayName: "Pasted image",
            reference: copy.path, localCopyPath: copy.path
        ))

        let up = try await a.sync()
        #expect(up.filesUploaded == 1)
        #expect(try await a.store.pendingCount() == 0)

        // B is another Mac: A's file isn't there.
        try FileManager.default.removeItem(at: copy)
        let down = try await b.sync()
        #expect(down.filesDownloaded == 1)
        let onB = try #require(await GRDBAttachmentRepository(queue: b.queue).attachments(for: task.id).first)
        let path = try #require(onB.localCopyPath)
        #expect(path.hasSuffix("Pasted image.png"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("PNG bytes".utf8))
        // Setting the downloaded copy is not a change to send back.
        #expect(try await b.store.pendingCount() == 0)

        // Nothing more moves on the next rounds.
        #expect(try await a.sync().filesUploaded == 0)
        #expect(await server.uploads == 1)
        #expect(try await b.sync().filesDownloaded == 0)
    }

    @Test func finderFile_isUploaded_andTheSameFileIsStoredOnce() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let task = WorkItem(title: "Review video")
        try await a.items.save(task)
        let video = try write("MP4 bytes", named: "preview.mp4")
        let attachments = GRDBAttachmentRepository(queue: a.queue)
        for _ in 0..<2 {
            try await attachments.save(Attachment(
                itemId: task.id, kind: .file, displayName: "preview.mp4",
                reference: video.path, bookmark: Data([9, 9])
            ))
        }
        let report = try await a.sync()
        #expect(report.filesUploaded == 2)
        #expect(await server.uploads == 1)
        #expect(await server.blobs.count == 1)
    }

    @Test func aMissingFile_isRetriedLater_notSkipped() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let task = WorkItem(title: "Gone")
        try await a.items.save(task)
        try await GRDBAttachmentRepository(queue: a.queue).save(Attachment(
            itemId: task.id, kind: .file, displayName: "moved.pdf", reference: "/nowhere/moved.pdf"
        ))
        #expect(try await a.sync().filesUploaded == 0)
        // B gets the row without a file and doesn't fail.
        let down = try await b.sync()
        #expect(down.filesDownloaded == 0)
        #expect(down.fileErrors == 0)
    }

    @Test func bigFiles_waitUntilOpened() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        let b = try Mac("B", server: server)
        let task = WorkItem(title: "Watch the demo")
        try await a.items.save(task)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-big-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let video = folder.appendingPathComponent("demo.mov")
        let bytes = Data((0..<(11 * 1_048_576)).map { UInt8($0 % 253) })
        try bytes.write(to: video)
        try await GRDBAttachmentRepository(queue: a.queue).save(Attachment(
            itemId: task.id, kind: .file, displayName: "demo.mov", reference: video.path
        ))
        #expect(try await a.sync().filesUploaded == 1)
        try FileManager.default.removeItem(at: folder) // B is another Mac

        #expect(try await b.sync().filesDownloaded == 0)
        let onB = try #require(await GRDBAttachmentRepository(queue: b.queue).attachments(for: task.id).first)
        #expect(onB.isOnServerOnly)
        #expect(onB.blobSize == bytes.count)

        let fetched = try #require(try await b.runner.fetchFile(attachmentId: onB.id.description))
        #expect(fetched.lastPathComponent == "demo.mov")
        #expect(try Data(contentsOf: fetched) == bytes)
        let after = try #require(await GRDBAttachmentRepository(queue: b.queue).attachments(for: task.id).first)
        #expect(!after.isOnServerOnly)
        #expect(try await b.store.pendingCount() == 0)
    }

    @Test func removingAnAttachment_deletesDownloadedCopies_notOriginals() async throws {
        let server = FakeServer()
        let a = try Mac("A", server: server)
        var b = try Mac("B", server: server)
        b.runner.downloadGrace = 0
        let task = WorkItem(title: "Two screenshots")
        try await a.items.save(task)
        let first = try write("first", named: "one.png")
        let second = try write("second", named: "two.png")
        let repoA = GRDBAttachmentRepository(queue: a.queue)
        let keep = Attachment(itemId: task.id, kind: .image, displayName: "one.png", reference: first.path, localCopyPath: first.path)
        let drop = Attachment(itemId: task.id, kind: .image, displayName: "two.png", reference: second.path, localCopyPath: second.path)
        try await repoA.save(keep)
        try await repoA.save(drop)
        try await a.sync()
        try FileManager.default.removeItem(at: first)
        let movedSecond = second.deletingLastPathComponent().appendingPathComponent("kept-two.png")
        try FileManager.default.moveItem(at: second, to: movedSecond) // hide it from B, keep it for A's check
        #expect(try await b.sync().filesDownloaded == 2)
        let synced = b.files.appendingPathComponent("Synced")
        #expect(try FileManager.default.contentsOfDirectory(atPath: synced.path).count == 2)

        try FileManager.default.moveItem(at: movedSecond, to: second)
        try await repoA.delete(drop.id)
        try await a.sync()
        let report = try await b.sync()
        #expect(report.filesRemoved == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: synced.path).count == 1)
        // A's own file is never touched.
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func fileNames_areSafe() {
        #expect(SyncRunner.safeFileName("a/b:c.txt") == "a-b-c.txt")
        #expect(SyncRunner.safeFileName("  ") == "file")
        #expect(SyncRunner.safeFileName(".hidden") == "file.hidden")
    }
}

