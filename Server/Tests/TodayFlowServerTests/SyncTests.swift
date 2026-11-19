import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import PostgresNIO
import Testing
@testable import TodayFlowServerKit

/// End-to-end tests against a real Postgres. Set TEST_PGPORT (and optionally
/// TEST_PGHOST / TEST_PGPASSWORD) to run them; each test starts from empty tables.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TEST_PGPORT"] != nil))
struct SyncTests {
    static let logger: Logger = {
        var logger = Logger(label: "test")
        logger.logLevel = .warning
        return logger
    }()

    static func makeClient() -> PostgresClient {
        let env = ProcessInfo.processInfo.environment
        return PostgresClient(
            configuration: postgresConfiguration([
                "PGHOST": env["TEST_PGHOST"] ?? "localhost",
                "PGPORT": env["TEST_PGPORT"] ?? "5432",
                "PGUSER": "todayflow",
                "PGPASSWORD": env["TEST_PGPASSWORD"] ?? "test",
                "PGDATABASE": "todayflow",
            ]),
            backgroundLogger: logger
        )
    }

    static let wipe: [PostgresQuery] = [
        "DROP TABLE IF EXISTS record, device, blob_owner, app_user, schema_version CASCADE",
        "DROP SEQUENCE IF EXISTS record_seq",
    ]

    /// Runs `body` against a server with empty tables.
    func withServer(
        configure: @Sendable (inout ServerConfig) -> Void = { _ in },
        _ body: @escaping @Sendable (any TestClientProtocol, Store) async throws -> Void
    ) async throws {
        let client = Self.makeClient()
        let logger = Self.logger
        let store = Store(client: client, logger: logger)
        var config = ServerConfig()
        // Test data is dated 2026-11-19; pin the clock after it.
        let fixedNow = parseTimestamp("2026-11-20T00:00:00Z")!
        config.now = { fixedNow }
        config.wrongCodeDelay = .zero
        configure(&config)
        var app = Application(
            router: buildRouter(store: store, config: config),
            services: [client],
            logger: logger
        )
        app.beforeServerStarts {
            for statement in Self.wipe { try await client.query(statement, logger: logger) }
            try await store.migrate()
        }
        try await app.test(.router) { client in
            try await body(client, store)
        }
    }

    func json<T: Encodable>(_ value: T) throws -> ByteBuffer {
        ByteBuffer(data: try JSONEncoder().encode(value))
    }

    func pair(_ client: any TestClientProtocol, code: String, name: String) async throws -> PairResponse {
        try await client.execute(
            uri: "/v1/pair", method: .post,
            body: json(PairRequest(pairingCode: code, deviceName: name))
        ) { response in
            #expect(response.status == .ok)
            return try JSONDecoder().decode(PairResponse.self, from: Data(buffer: response.body))
        }
    }

    func pairStatus(_ client: any TestClientProtocol, code: String) async throws -> HTTPResponse.Status {
        try await client.execute(
            uri: "/v1/pair", method: .post,
            body: json(PairRequest(pairingCode: code, deviceName: "x"))
        ) { $0.status }
    }

    /// A user with one paired device.
    func device(_ client: any TestClientProtocol, _ store: Store, user: String, name: String) async throws -> PairResponse {
        let existing = try await store.users().contains { $0.name == user }
        let code = existing ? try await store.resetPairingCode(user: user) : try await store.addUser(name: user).pairingCode
        return try await pair(client, code: code, name: name)
    }

    func push(_ client: any TestClientProtocol, token: String, _ changes: [Change]) async throws -> PushResponse {
        try await client.execute(
            uri: "/v1/push", method: .post,
            headers: [.authorization: "Bearer \(token)"],
            body: json(PushRequest(changes: changes))
        ) { response in
            #expect(response.status == .ok)
            return try JSONDecoder().decode(PushResponse.self, from: Data(buffer: response.body))
        }
    }

    func pull(_ client: any TestClientProtocol, token: String, since: Int64 = 0, limit: Int = 500) async throws -> PullResponse {
        try await client.execute(
            uri: "/v1/pull?since=\(since)&limit=\(limit)", method: .get,
            headers: [.authorization: "Bearer \(token)"]
        ) { response in
            #expect(response.status == .ok)
            return try JSONDecoder().decode(PullResponse.self, from: Data(buffer: response.body))
        }
    }

    func status(_ client: any TestClientProtocol, token: String) async throws -> StatusResponse {
        try await client.execute(
            uri: "/v1/status", method: .get, headers: [.authorization: "Bearer \(token)"]
        ) { response in
            #expect(response.status == .ok)
            return try JSONDecoder().decode(StatusResponse.self, from: Data(buffer: response.body))
        }
    }

    func task(_ id: String, title: String, at: String, op: String = "upsert") -> Change {
        Change(
            entity: "work_item", id: id, op: op, changedAt: at,
            data: op == "delete" ? nil : .object(["id": .string(id), "title": .string(title), "priority": .number(3)])
        )
    }

    func taskData(_ id: String, _ title: String) -> JSONValue {
        .object(["id": .string(id), "title": .string(title), "priority": .number(3)])
    }

    // MARK: - Sign-in

    @Test func health_needsNoSignIn() async throws {
        try await withServer { client, _ in
            try await client.execute(uri: "/health", method: .get) { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test func wrongPairingCode_isRejected_andRightOneWorksInAnyCase() async throws {
        try await withServer { client, store in
            let code = try await store.addUser(name: "Alex").pairingCode
            #expect(try await pairStatus(client, code: "000000-000000-000000-000000") == .unauthorized)
            #expect(try await pairStatus(client, code: "") == .unauthorized)
            // Dashes and case do not matter.
            let sloppy = code.replacingOccurrences(of: "-", with: "").uppercased()
            #expect(try await pairStatus(client, code: sloppy) == .ok)
        }
    }

    @Test func manyWrongCodes_lockPairingForEveryone() async throws {
        try await withServer(configure: { $0.pairingLimiter = PairingLimiter(limit: 3, window: 600) }) { client, store in
            let code = try await store.addUser(name: "Alex").pairingCode
            for _ in 0..<3 {
                #expect(try await pairStatus(client, code: "aaaaaa-aaaaaa-aaaaaa-aaaaaa") == .unauthorized)
            }
            // Even the right code is refused while locked.
            #expect(try await pairStatus(client, code: code) == .tooManyRequests)
        }
    }

    @Test func missingOrUnknownToken_isRejected() async throws {
        try await withServer { client, _ in
            try await client.execute(uri: "/v1/pull", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
            try await client.execute(
                uri: "/v1/pull", method: .get, headers: [.authorization: "Bearer abc"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test func revokedDevice_isRejected_andAmbiguousNamesAreRefused() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "MacBook")
            _ = try await device(client, store, user: "Test", name: "MacBook")
            await #expect(throws: Store.StoreError.ambiguousDevice("MacBook")) {
                try await store.revokeDevice(idOrName: "MacBook")
            }
            #expect(try await store.revokeDevice(idOrName: a.deviceId) == 1)
            try await client.execute(
                uri: "/v1/status", method: .get, headers: [.authorization: "Bearer \(a.token)"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
            // Now only one active "MacBook" is left, so the name works.
            #expect(try await store.revokeDevice(idOrName: "MacBook") == 1)
        }
    }

    @Test func resetCode_oldCodeStops_pairedDevicesKeepWorking() async throws {
        try await withServer { client, store in
            let old = try await store.addUser(name: "Alex").pairingCode
            let mac = try await pair(client, code: old, name: "Mac")
            let new = try await store.resetPairingCode(user: "Alex")
            #expect(try await pairStatus(client, code: old) == .unauthorized)
            #expect(try await pairStatus(client, code: new) == .ok)
            #expect(try await status(client, token: mac.token).ok)
        }
    }

    @Test func duplicateUserName_isRefused() async throws {
        try await withServer { _, store in
            _ = try await store.addUser(name: "Alex")
            await #expect(throws: Store.StoreError.userExists("Alex")) {
                try await store.addUser(name: "Alex")
            }
        }
    }

    // MARK: - Sync within one user

    @Test func changeFromOneDevice_reachesTheOther_butNotItself() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let b = try await device(client, store, user: "Alex", name: "Mac B")
            let pushed = try await push(client, token: a.token, [
                task("T1", title: "Buy milk", at: "2026-11-19T10:00:00.000Z"),
            ])
            #expect(pushed.results.map(\.status) == ["accepted"])

            let forB = try await pull(client, token: b.token)
            #expect(forB.changes.count == 1)
            #expect(forB.changes.first?.data == taskData("T1", "Buy milk"))
            #expect(forB.changes.first?.changedAt == "2026-11-19T10:00:00.000Z")
            #expect(forB.changes.first?.deviceId == a.deviceId)
            #expect(forB.more == false)

            // A does not get its own change back, but its cursor still advances.
            let forA = try await pull(client, token: a.token)
            #expect(forA.changes.isEmpty)
            #expect(forA.next == forB.next)

            let again = try await pull(client, token: b.token, since: forB.next)
            #expect(again.changes.isEmpty)
            #expect(again.next == forB.next)
        }
    }

    @Test func newerEditWins_andOlderEditIsStaleWithTheWinnerReturned() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let b = try await device(client, store, user: "Alex", name: "Mac B")
            _ = try await push(client, token: a.token, [task("T1", title: "From A, later", at: "2026-11-19T10:05:00Z")])
            let late = try await push(client, token: b.token, [task("T1", title: "From B, earlier", at: "2026-11-19T10:01:00Z")])
            #expect(late.results.first?.status == "stale")
            #expect(late.results.first?.current?.data == taskData("T1", "From A, later"))

            let newer = try await push(client, token: b.token, [task("T1", title: "From B, newest", at: "2026-11-19T10:09:00Z")])
            #expect(newer.results.first?.status == "accepted")
            let forA = try await pull(client, token: a.token)
            #expect(forA.changes.count == 1)
            #expect(forA.changes.first?.data == taskData("T1", "From B, newest"))
        }
    }

    @Test func delete_syncsAndKeepsLastData() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let b = try await device(client, store, user: "Alex", name: "Mac B")
            _ = try await push(client, token: a.token, [task("T1", title: "Temp", at: "2026-11-19T10:00:00Z")])
            _ = try await push(client, token: a.token, [task("T1", title: "", at: "2026-11-19T10:01:00Z", op: "delete")])
            let forB = try await pull(client, token: b.token)
            #expect(forB.changes.count == 1)
            #expect(forB.changes.first?.op == "delete")
            #expect(forB.changes.first?.data != nil)
        }
    }

    @Test func pull_pagesInOrder() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let b = try await device(client, store, user: "Alex", name: "Mac B")
            let changes = (1...5).map { task("T\($0)", title: "Task \($0)", at: "2026-11-19T10:00:0\($0)Z") }
            _ = try await push(client, token: a.token, changes)

            let first = try await pull(client, token: b.token, limit: 2)
            #expect(first.changes.map(\.id) == ["T1", "T2"])
            #expect(first.more)
            let second = try await pull(client, token: b.token, since: first.next, limit: 2)
            #expect(second.changes.map(\.id) == ["T3", "T4"])
            let third = try await pull(client, token: b.token, since: second.next, limit: 2)
            #expect(third.changes.map(\.id) == ["T5"])
            #expect(third.more == false)
        }
    }

    @Test func badChanges_areRejected() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            for bad in [
                Change(entity: "work_item", id: "T1", op: "explode", changedAt: "2026-11-19T10:00:00Z", data: .null),
                Change(entity: "work_item", id: "T1", op: "upsert", changedAt: "yesterday", data: .null),
                Change(entity: "work_item", id: "T1", op: "upsert", changedAt: "2026-11-19T10:00:00Z", data: nil),
                Change(entity: "", id: "T1", op: "delete", changedAt: "2026-11-19T10:00:00Z", data: nil),
                Change(entity: String(repeating: "e", count: 65), id: "T1", op: "delete",
                       changedAt: "2026-11-19T10:00:00Z", data: nil),
            ] {
                try await client.execute(
                    uri: "/v1/push", method: .post,
                    headers: [.authorization: "Bearer \(a.token)"],
                    body: json(PushRequest(changes: [bad]))
                ) { response in
                    #expect(response.status == .badRequest)
                }
            }
            #expect(try await status(client, token: a.token).records == 0)
        }
    }

    @Test func changeDatedFarInTheFuture_isRefused() async throws {
        let now = parseTimestamp("2026-11-19T10:00:00Z")!
        try await withServer(configure: { $0.now = { now } }) { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let ok = try await push(client, token: a.token, [task("T1", title: "ok", at: "2026-11-19T10:05:00Z")])
            #expect(ok.results.first?.status == "accepted")
            try await client.execute(
                uri: "/v1/push", method: .post,
                headers: [.authorization: "Bearer \(a.token)"],
                body: json(PushRequest(changes: [task("T2", title: "late", at: "2026-11-19T12:00:00Z")]))
            ) { response in
                #expect(response.status == .badRequest)
                #expect(String(buffer: response.body).contains("clock"))
            }
        }
    }

    @Test func pushLargerThanTheDefaultUploadLimit_isAccepted() async throws {
        try await withServer { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let note = String(repeating: "x", count: 6_000)
            let changes = (1...500).map { index in
                Change(
                    entity: "work_item", id: "T\(index)", op: "upsert", changedAt: "2026-11-19T10:00:00Z",
                    data: .object(["id": .string("T\(index)"), "description_md": .string(note)])
                )
            }
            #expect(try JSONEncoder().encode(PushRequest(changes: changes)).count > 2 * 1024 * 1024)
            let result = try await push(client, token: a.token, changes)
            #expect(result.results.count == 500)
            #expect(result.results.allSatisfy { $0.status == "accepted" })
        }
    }

    // MARK: - Isolation between users

    @Test func users_neverSeeEachOthersRows() async throws {
        try await withServer { client, store in
            let real = try await device(client, store, user: "Real", name: "MacBook Pro")
            let test = try await device(client, store, user: "Test", name: "Studio")
            _ = try await push(client, token: real.token, [task("T1", title: "Real task", at: "2026-11-19T10:00:00Z")])

            // Test's devices see nothing of Real's.
            let forTest = try await pull(client, token: test.token)
            #expect(forTest.changes.isEmpty)
            #expect(try await status(client, token: test.token).records == 0)

            // The same row id in another user is a different row: no conflict,
            // and an "older" edit there is not stale.
            let other = try await push(client, token: test.token, [task("T1", title: "Test task", at: "2026-11-19T09:00:00Z")])
            #expect(other.results.first?.status == "accepted")

            let real2 = try await device(client, store, user: "Real", name: "iMac")
            let forReal = try await pull(client, token: real2.token)
            #expect(forReal.changes.map(\.data) == [taskData("T1", "Real task")])
            #expect(try await status(client, token: real.token).records == 1)
        }
    }

    @Test func deleteUser_removesTheirDataAndSignsTheirDevicesOut() async throws {
        try await withServer { client, store in
            let real = try await device(client, store, user: "Real", name: "MacBook Pro")
            let test = try await device(client, store, user: "Test", name: "Studio")
            _ = try await push(client, token: test.token, [task("T1", title: "Test", at: "2026-11-19T10:00:00Z")])
            _ = try await push(client, token: real.token, [task("T2", title: "Real", at: "2026-11-19T10:00:00Z")])

            try await store.deleteUser(name: "Test")
            try await client.execute(
                uri: "/v1/status", method: .get, headers: [.authorization: "Bearer \(test.token)"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
            #expect(try await store.users().map(\.name) == ["Real"])
            #expect(try await status(client, token: real.token).records == 1)
            await #expect(throws: Store.StoreError.noSuchUser("Test")) {
                try await store.deleteUser(name: "Test")
            }
        }
    }

    // MARK: - Blobs

    func blobDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("todayflow-blobs-\(UUID().uuidString)", isDirectory: true)
    }

    func auth(_ token: String) -> HTTPFields { [.authorization: "Bearer \(token)"] }

    @Test func pairAndStatus_tellTheDeviceItsUserName() async throws {
        try await withServer { client, store in
            let paired = try await device(client, store, user: "Alex", name: "MacBook")
            #expect(paired.userName == "Alex")
            try await client.execute(uri: "/v1/status", method: .get, headers: auth(paired.token)) { response in
                let status = try JSONDecoder().decode(StatusResponse.self, from: Data(buffer: response.body))
                #expect(status.userName == "Alex")
            }
        }
    }

    @Test func blob_uploadDownloadAndDeduplicateWithinAUser() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await withServer(configure: { $0.blobs = BlobStore(root: root) }) { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let b = try await device(client, store, user: "Alex", name: "Mac B")
            let bytes = Data((0..<50_000).map { UInt8($0 % 251) })
            let hash = BlobStore.sha256(bytes)

            try await client.execute(uri: "/v1/blobs/\(hash)", method: .head, headers: auth(b.token)) {
                #expect($0.status == .notFound)
            }
            try await client.execute(
                uri: "/v1/blobs/\(hash)", method: .put, headers: auth(a.token), body: ByteBuffer(data: bytes)
            ) { #expect($0.status == .created) }
            try await client.execute(
                uri: "/v1/blobs/\(hash)", method: .put, headers: auth(b.token), body: ByteBuffer(data: bytes)
            ) { #expect($0.status == .ok) }
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .head, headers: auth(b.token)) {
                #expect($0.status == .ok)
            }
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .get, headers: auth(b.token)) { response in
                #expect(response.status == .ok)
                #expect(Data(buffer: response.body) == bytes)
            }
        }
    }

    @Test func blob_anotherUsersFileLooksMissing_andCannotBeClaimedWithoutTheBytes() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await withServer(configure: { $0.blobs = BlobStore(root: root) }) { client, store in
            let real = try await device(client, store, user: "Real", name: "MacBook Pro")
            let test = try await device(client, store, user: "Test", name: "Studio")
            let bytes = Data("private photo".utf8)
            let hash = BlobStore.sha256(bytes)
            try await client.execute(
                uri: "/v1/blobs/\(hash)", method: .put, headers: auth(real.token), body: ByteBuffer(data: bytes)
            ) { #expect($0.status == .created) }

            // Test cannot tell the file exists, nor download it.
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .head, headers: auth(test.token)) {
                #expect($0.status == .notFound)
            }
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .get, headers: auth(test.token)) {
                #expect($0.status == .notFound)
            }
            // Knowing the hash is not enough: claiming needs the exact bytes.
            try await client.execute(
                uri: "/v1/blobs/\(hash)", method: .put, headers: auth(test.token), body: ByteBuffer(string: "guess")
            ) { #expect($0.status == .badRequest) }
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .get, headers: auth(test.token)) {
                #expect($0.status == .notFound)
            }
            // A user who really has the same file gets "created", like a new file.
            try await client.execute(
                uri: "/v1/blobs/\(hash)", method: .put, headers: auth(test.token), body: ByteBuffer(data: bytes)
            ) { #expect($0.status == .created) }
        }
    }

    @Test func blobCleanup_removesOnlyFilesNobodyOwns() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let blobs = BlobStore(root: root)
        try await withServer(configure: { $0.blobs = blobs }) { client, store in
            let real = try await device(client, store, user: "Real", name: "MacBook Pro")
            let test = try await device(client, store, user: "Test", name: "Studio")
            let shared = Data("both have this".utf8)
            let onlyTest = Data("only test has this".utf8)
            for (token, data) in [(real.token, shared), (test.token, shared), (test.token, onlyTest)] {
                try await client.execute(
                    uri: "/v1/blobs/\(BlobStore.sha256(data))", method: .put,
                    headers: auth(token), body: ByteBuffer(data: data)
                ) { _ in }
            }
            try await store.deleteUser(name: "Test")
            // Just uploaded: protected for an hour.
            #expect(blobs.removeUnowned(keeping: try await store.ownedBlobHashes()) == 0)
            #expect(blobs.removeUnowned(keeping: try await store.ownedBlobHashes(), minimumAge: 0) == 1)
            #expect(blobs.exists(BlobStore.sha256(shared)))
            #expect(!blobs.exists(BlobStore.sha256(onlyTest)))
        }
    }

    @Test func blob_unusedFilesAreReleasedAfterTheGracePeriod_usedOnesKept() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await withServer(configure: { $0.blobs = BlobStore(root: root) }) { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let used = Data("attached screenshot".utf8)
            let removed = Data("attachment that was deleted".utf8)
            for data in [used, removed] {
                try await client.execute(
                    uri: "/v1/blobs/\(BlobStore.sha256(data))", method: .put, headers: auth(a.token), body: ByteBuffer(data: data)
                ) { _ in }
            }
            func attachment(_ id: String, _ data: Data, op: String = "upsert", at: String) -> Change {
                Change(entity: "attachment", id: id, op: op, changedAt: at,
                       data: op == "delete" ? nil : .object(["id": .string(id), "blob_sha256": .string(BlobStore.sha256(data)), "deleted_at": .null]))
            }
            _ = try await push(client, token: a.token, [
                attachment("1", used, at: "2026-01-01T00:00:00.000Z"),
                attachment("2", removed, at: "2026-01-01T00:00:00.000Z"),
            ])
            _ = try await push(client, token: a.token, [attachment("2", removed, op: "delete", at: "2026-01-02T00:00:00.000Z")])

            // Marked, but kept during the grace period.
            #expect(try await store.releaseUnusedBlobs(grace: 3600) == 0)
            #expect(try await store.ownedBlobHashes() == [BlobStore.sha256(used), BlobStore.sha256(removed)])
            // Past it, only the unused one is released.
            #expect(try await store.releaseUnusedBlobs(grace: -1) == 1)
            #expect(try await store.ownedBlobHashes() == [BlobStore.sha256(used)])
        }
    }

    @Test func blob_streamsLargeFiles_andRefusesOnesOverTheLimit() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await withServer(configure: { $0.blobs = BlobStore(root: root); $0.maxBlobBytes = 6 * 1_048_576 }) { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let big = Data((0..<(5 * 1_048_576)).map { UInt8($0 % 251) })
            let hash = BlobStore.sha256(big)
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .put, headers: auth(a.token), body: ByteBuffer(data: big)) {
                #expect($0.status == .created)
            }
            try await client.execute(uri: "/v1/blobs/\(hash)", method: .get, headers: auth(a.token)) { response in
                #expect(response.status == .ok)
                #expect(Data(buffer: response.body) == big)
            }
            let tooBig = Data(repeating: 7, count: 7 * 1_048_576)
            try await client.execute(
                uri: "/v1/blobs/\(BlobStore.sha256(tooBig))", method: .put, headers: auth(a.token), body: ByteBuffer(data: tooBig)
            ) { #expect($0.status == .contentTooLarge) }
            #expect(!BlobStore(root: root).exists(BlobStore.sha256(tooBig)))
        }
    }

    @Test func blob_rejectsWrongHashBadNameAndNoSignIn() async throws {
        let root = blobDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await withServer(configure: { $0.blobs = BlobStore(root: root) }) { client, store in
            let a = try await device(client, store, user: "Alex", name: "Mac A")
            let wrong = String(repeating: "0", count: 64)
            try await client.execute(
                uri: "/v1/blobs/\(wrong)", method: .put, headers: auth(a.token), body: ByteBuffer(string: "hello")
            ) { #expect($0.status == .badRequest) }
            try await client.execute(uri: "/v1/blobs/..%2Fetc", method: .get, headers: auth(a.token)) {
                #expect($0.status == .badRequest)
            }
            try await client.execute(uri: "/v1/blobs/\(wrong)", method: .get) {
                #expect($0.status == .unauthorized)
            }
            try await client.execute(uri: "/v1/blobs/\(wrong)", method: .get, headers: auth(a.token)) {
                #expect($0.status == .notFound)
            }
            let leftovers = (try? FileManager.default.subpathsOfDirectory(atPath: root.path)) ?? []
            #expect(leftovers.filter { $0.count > 3 }.isEmpty)
        }
    }

    // MARK: - Upgrade from the single-user schema

    @Test func upgrade_replacesEmptySingleUserTables_butRefusesWhenTheyHoldRows() async throws {
        let client = Self.makeClient()
        let logger = Self.logger
        let store = Store(client: client, logger: logger)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { await client.run() }
            let v1: [PostgresQuery] = [
                "CREATE TABLE record (entity TEXT, id TEXT, data JSONB, deleted BOOLEAN, changed_at TIMESTAMPTZ, device_id TEXT, seq BIGINT, PRIMARY KEY (entity, id))",
                "CREATE TABLE device (id TEXT PRIMARY KEY, name TEXT, token_hash TEXT, created_at TIMESTAMPTZ, last_seen_at TIMESTAMPTZ, revoked BOOLEAN)",
            ]
            for statement in Self.wipe + v1 { try await client.query(statement, logger: logger) }
            try await client.query("INSERT INTO device VALUES ('d', 'old', 'h', now(), NULL, FALSE)", logger: logger)
            await #expect(throws: Store.StoreError.self) { try await store.migrate() }

            try await client.query("DELETE FROM device", logger: logger)
            try await store.migrate()
            try await store.migrate()  // idempotent
            _ = try await store.addUser(name: "Alex")
            #expect(try await store.users().count == 1)
            group.cancelAll()
        }
    }
}
