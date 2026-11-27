import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowSync

/// The way in to the server can be narrower than the server: Cloudflare's
/// tunnel refuses uploads over 100 MB and may just drop the connection.
/// One file like that must never keep the tasks from syncing (the iPhone
/// that showed "Last synced: Never" with 412 changes waiting).
struct ConnectionLimitTests {
    enum Drop { case connection, contentTooLarge }

    /// The fake server behind a proxy that refuses bodies over `limit`.
    struct ProxyTransport: SyncTransport {
        let inner: FakeTransport
        let limit: Int
        var drop: Drop = .connection
        var reachable = true
        /// Drops every upload, whatever its size (a flaky connection).
        var dropAll = false

        func pull(since: Int64, limit: Int) async throws -> SyncClient.PullPage {
            guard reachable else { throw SyncError.network("The network connection was lost.") }
            return try await inner.pull(since: since, limit: limit)
        }
        func push(_ changes: [SyncChange]) async throws -> [SyncClient.PushResult] {
            try await inner.push(changes)
        }
        func hasBlob(_ sha256: String) async throws -> Bool { try await inner.hasBlob(sha256) }
        func putBlob(file: URL, sha256: String) async throws {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if dropAll || size > limit {
                switch drop {
                case .connection: throw SyncError.network("The network connection was lost.")
                case .contentTooLarge: throw SyncError.server(status: 413, message: "")
                }
            }
            try await inner.putBlob(file: file, sha256: sha256)
        }
        func getBlob(_ sha256: String, to destination: URL) async throws -> Bool {
            try await inner.getBlob(sha256, to: destination)
        }
        func isReachable() async -> Bool { reachable }
    }

    struct Phone {
        let items: GRDBWorkItemRepository
        let attachments: GRDBAttachmentRepository
        let store: SyncStore
        var runner: SyncRunner

        init(server: FakeServer, transport: (FakeTransport) -> ProxyTransport) throws {
            let queue = try TodayFlowDatabase.makeInMemory()
            items = GRDBWorkItemRepository(queue: queue)
            attachments = GRDBAttachmentRepository(queue: queue)
            store = SyncStore(queue: queue)
            let files = FileManager.default.temporaryDirectory.appendingPathComponent("tf-files-\(UUID().uuidString)")
            runner = SyncRunner(
                store: store,
                client: transport(FakeTransport(server: server, device: "iPhone")),
                filesDirectory: files
            )
            runner.proxyFileBytes = 20
        }

        /// A task with an attachment whose file has `bytes` bytes.
        func taskWithFile(_ title: String, bytes: Int) async throws -> WorkItem {
            let task = WorkItem(title: title)
            try await items.save(task)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-src-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("\(title).mov")
            try Data(repeating: 7, count: bytes).write(to: file)
            try await attachments.save(Attachment(
                itemId: task.id, kind: .file, displayName: "\(title).mov", reference: file.path, localCopyPath: file.path
            ))
            return task
        }
    }

    @Test(arguments: [Drop.connection, .contentTooLarge])
    func aFileTooBigForTheProxy_isSetAside_andTheTasksStillSync(drop: Drop) async throws {
        let server = FakeServer()
        let phone = try Phone(server: server) { ProxyTransport(inner: $0, limit: 20, drop: drop) }
        let big = try await phone.taskWithFile("Dive video", bytes: 100)
        let plain = WorkItem(title: "Call the bank")
        try await phone.items.save(plain)

        let report = try await phone.runner.run()

        #expect(report.sent > 0)
        #expect(await server.data("work_item", plain.id.description) != nil)
        #expect(await server.data("work_item", big.id.description) != nil)
        #expect(try await phone.store.pendingCount() == 0)
        let skipped = try await phone.store.skippedBlobs()
        #expect(skipped.count == 1)
        #expect(skipped.first?.reason.contains("100 MB") == true)
        // Set aside, not retried every 10 seconds.
        let again = try await phone.runner.run()
        #expect(again.fileErrors == 0)
        #expect(await server.uploads == 0)
    }

    @Test func aSmallFileWhoseUploadDropped_isRetried_andTheTasksStillSync() async throws {
        let server = FakeServer()
        var phone = try Phone(server: server) { ProxyTransport(inner: $0, limit: 20, dropAll: true) }
        let task = try await phone.taskWithFile("Receipt", bytes: 10)

        let first = try await phone.runner.run()
        #expect(first.fileErrors == 1)
        #expect(await server.data("work_item", task.id.description) != nil)
        #expect(try await phone.store.skippedBlobs().isEmpty)

        // The connection is fine again: the file goes up.
        phone.runner = SyncRunner(
            store: phone.store,
            client: ProxyTransport(inner: FakeTransport(server: server, device: "iPhone"), limit: 20),
            filesDirectory: phone.runner.filesDirectory
        )
        let second = try await phone.runner.run()
        #expect(second.filesUploaded == 1)
        #expect(await server.uploads == 1)
    }

    @Test func whenTheServerIsGone_theRoundStops_andNothingIsLost() async throws {
        let server = FakeServer()
        let phone = try Phone(server: server) { ProxyTransport(inner: $0, limit: 20, reachable: false) }
        _ = try await phone.taskWithFile("Dive video", bytes: 100)

        await #expect(throws: SyncError.network("The network connection was lost.")) {
            try await phone.runner.run()
        }
        #expect(try await phone.store.pendingCount() > 0)
        #expect(try await phone.store.skippedBlobs().isEmpty)
    }
}
