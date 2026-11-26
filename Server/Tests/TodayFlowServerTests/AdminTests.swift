import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import PostgresNIO
import Testing
@testable import TodayFlowServerKit

/// Admin page tests. An extension of `SyncTests` so they share its
/// serialization: both wipe the same tables.
extension SyncTests {
    static let adminPassword = "correct horse battery"

    struct AdminHarness: Sendable {
        let root: URL
        var catalog: BackupCatalog {
            BackupCatalog(backups: root.appendingPathComponent("backups"), control: root.appendingPathComponent("control"))
        }
    }

    func withAdmin(
        configure: @Sendable (inout AdminConfig) -> Void = { _ in },
        _ body: @escaping @Sendable (any TestClientProtocol, Store, AdminHarness) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("todayflow-admin-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let harness = AdminHarness(root: root)
        try FileManager.default.createDirectory(at: harness.catalog.backups, withIntermediateDirectories: true)

        let client = Self.makeClient()
        let logger = Self.logger
        let store = Store(client: client, logger: logger)
        var config = AdminConfig(
            password: Self.adminPassword,
            backups: harness.catalog,
            blobs: BlobStore(root: root.appendingPathComponent("blobs"))
        )
        config.wrongPasswordDelay = .zero
        configure(&config)
        var app = Application(router: buildAdminRouter(store: store, config: config), services: [client], logger: logger)
        app.beforeServerStarts {
            for statement in Self.wipe { try await client.query(statement, logger: logger) }
            try await store.migrate()
        }
        try await app.test(.router) { client in
            try await body(client, store, harness)
        }
    }

    struct Signed: Sendable {
        let cookie: String
        let csrf: String
    }

    func form(_ fields: [String: String]) -> ByteBuffer {
        ByteBuffer(string: fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
        }.joined(separator: "&"))
    }

    var formHeaders: HTTPFields { [.contentType: "application/x-www-form-urlencoded"] }

    func signIn(_ client: any TestClientProtocol) async throws -> Signed {
        let cookie = try await client.execute(
            uri: "/login", method: .post, headers: formHeaders, body: form(["password": Self.adminPassword])
        ) { response -> String in
            #expect(response.status == .seeOther)
            let setCookie = try #require(response.headers[.setCookie])
            #expect(setCookie.contains("HttpOnly"))
            #expect(setCookie.contains("SameSite=Strict"))
            return String(setCookie.split(separator: ";")[0])
        }
        let page = try await get(client, "/", cookie: cookie)
        let csrf = try #require(page.firstMatch(of: /name="csrf" value="([0-9a-f]{64})"/)?.1)
        return Signed(cookie: cookie, csrf: String(csrf))
    }

    func get(_ client: any TestClientProtocol, _ uri: String, cookie: String?) async throws -> String {
        var headers: HTTPFields = [:]
        if let cookie { headers[.cookie] = cookie }
        return try await client.execute(uri: uri, method: .get, headers: headers) { String(buffer: $0.body) }
    }

    func post(
        _ client: any TestClientProtocol, _ uri: String, _ signed: Signed?, _ fields: [String: String] = [:],
        csrf: String? = nil
    ) async throws -> (status: HTTPResponse.Status, location: String?, body: String) {
        var headers = formHeaders
        if let signed { headers[.cookie] = signed.cookie }
        var all = fields
        if let token = csrf ?? signed?.csrf { all["csrf"] = token }
        return try await client.execute(uri: uri, method: .post, headers: headers, body: form(all)) {
            ($0.status, $0.headers[.location], String(buffer: $0.body))
        }
    }

    // MARK: - Tests

    @Test func admin_pagesNeedSignIn() async throws {
        try await withAdmin { client, _, _ in
            for path in ["/", "/users", "/devices", "/backups", "/users/delete?name=x"] {
                try await client.execute(uri: path, method: .get) { response in
                    #expect(response.status == .seeOther)
                    #expect(response.headers[.location] == "/login")
                }
            }
            let added = try await post(client, "/users/add", nil, ["name": "Mallory"], csrf: String(repeating: "0", count: 64))
            #expect(added.location == "/login")
        }
    }

    @Test func admin_wrongPasswordFails_andRepeatedFailuresLockSignIn() async throws {
        try await withAdmin(configure: { $0.loginLimiter = PairingLimiter(limit: 2, window: 600) }) { client, _, _ in
            for _ in 0..<2 {
                let wrong = try await post(client, "/login", nil, ["password": "guess guess guess"])
                #expect(wrong.status == .unauthorized)
                #expect(wrong.body.contains("Wrong password"))
            }
            let locked = try await post(client, "/login", nil, ["password": Self.adminPassword])
            #expect(locked.status == .tooManyRequests)
        }
    }

    @Test func admin_securityHeadersAreSet() async throws {
        try await withAdmin { client, _, _ in
            try await client.execute(uri: "/login", method: .get) { response in
                #expect(response.headers[.contentSecurityPolicy]?.contains("default-src 'none'") == true)
                #expect(response.headers[.contentSecurityPolicy]?.contains("frame-ancestors 'none'") == true)
                #expect(response.headers[.xContentTypeOptions] == "nosniff")
                #expect(response.headers[.cacheControl] == "no-store")
            }
        }
    }

    @Test func admin_changesWithoutTheFormTokenAreRefused() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            let forged = try await post(client, "/users/add", signed, ["name": "Mallory"], csrf: String(repeating: "a", count: 64))
            #expect(forged.location == "/login")
            #expect(try await store.users().isEmpty)
        }
    }

    @Test func admin_addUserShowsTheCodeOnce_andItPairs() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            let added = try await post(client, "/users/add", signed, ["name": "Alex"])
            #expect(added.status == .ok)
            let code = try #require(added.body.firstMatch(of: /class="code">([0-9a-f-]{27})</)?.1)
            #expect(try await store.pair(code: String(code), deviceName: "Mac") != nil)
            // The users page lists the user but never shows a code.
            let users = try await get(client, "/users", cookie: signed.cookie)
            #expect(users.contains("Alex"))
            #expect(!users.contains(String(code)))

            let duplicate = try await post(client, "/users/add", signed, ["name": "Alex"])
            #expect(duplicate.status == .conflict)
        }
    }

    @Test func admin_newPairingCodeReplacesTheOldOne() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            let old = try await store.addUser(name: "Alex").pairingCode
            let reset = try await post(client, "/users/code", signed, ["name": "Alex"])
            let new = try #require(reset.body.firstMatch(of: /class="code">([0-9a-f-]{27})</)?.1)
            #expect(try await store.pair(code: old, deviceName: "x") == nil)
            #expect(try await store.pair(code: String(new), deviceName: "x") != nil)
        }
    }

    @Test func admin_showsThePublicSyncAddress() async throws {
        try await withAdmin(configure: { $0.publicURL = "https://sync.example.com" }) { client, _, _ in
            let signed = try await signIn(client)
            let overview = try await get(client, "/", cookie: signed.cookie)
            #expect(overview.contains("https://sync.example.com"))
            let added = try await post(client, "/users/add", signed, ["name": "Alex"])
            #expect(added.body.contains("Server address: <strong class=\"address\">https://sync.example.com</strong>"))
        }
    }

    @Test func admin_deleteNeedsTheNameTyped() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            _ = try await store.addUser(name: "Test")
            let confirm = try await get(client, "/users/delete?name=Test", cookie: signed.cookie)
            #expect(confirm.contains("Type <strong>Test</strong> to confirm"))

            let mistyped = try await post(client, "/users/delete", signed, ["name": "Test", "confirm": "test"])
            #expect(mistyped.status == .seeOther)
            #expect(try await store.users().count == 1)

            let deleted = try await post(client, "/users/delete", signed, ["name": "Test", "confirm": "Test"])
            #expect(deleted.location == "/users?done=deleted")
            #expect(try await store.users().isEmpty)
        }
    }

    @Test func admin_signOutDevice() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            let code = try await store.addUser(name: "Alex").pairingCode
            let paired = try #require(try await store.pair(code: code, deviceName: "MacBook Pro"))
            let page = try await get(client, "/devices", cookie: signed.cookie)
            #expect(page.contains("MacBook Pro"))
            _ = try await post(client, "/devices/revoke", signed, ["id": paired.caller.deviceId])
            #expect(try await store.caller(forToken: paired.token) == nil)
        }
    }

    @Test func admin_namesAreEscaped() async throws {
        try await withAdmin { client, store, _ in
            let signed = try await signIn(client)
            let code = try await store.addUser(name: "<script>alert(1)</script>").pairingCode
            _ = try await store.pair(code: code, deviceName: "\"><img src=x onerror=alert(1)>")
            for path in ["/", "/users", "/devices"] {
                let html = try await get(client, path, cookie: signed.cookie)
                #expect(!html.contains("<script>alert"))
                #expect(!html.contains("<img src=x"))
            }
        }
    }

    @Test func admin_backupNowAndDownload() async throws {
        try await withAdmin { client, _, harness in
            let signed = try await signIn(client)
            let dump = harness.catalog.backups.appendingPathComponent("todayflow-20261119-104717.dump")
            try Data("PGDMP fake".utf8).write(to: dump)

            let page = try await get(client, "/backups", cookie: signed.cookie)
            #expect(page.contains("19 Nov 2026") || page.contains("Download"))

            let requested = try await post(client, "/backups/now", signed)
            #expect(requested.location == "/backups?done=backup")
            #expect(harness.catalog.isBackupPending)

            try await client.execute(
                uri: "/backups/todayflow-20261119-104717.dump", method: .get, headers: [.cookie: signed.cookie]
            ) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "PGDMP fake")
            }
            // Only real dump names; no path tricks; no download when signed out.
            for bad in ["..%2F..%2Fetc%2Fpasswd", "secrets.env", "todayflow-1.dump"] {
                try await client.execute(uri: "/backups/\(bad)", method: .get, headers: [.cookie: signed.cookie]) {
                    #expect($0.status == .notFound)
                }
            }
            try await client.execute(uri: "/backups/todayflow-20261119-104717.dump", method: .get) {
                #expect($0.status == .seeOther)
            }
        }
    }

    @Test func admin_signOutEndsTheSession() async throws {
        try await withAdmin { client, _, _ in
            let signed = try await signIn(client)
            _ = try await post(client, "/logout", signed)
            try await client.execute(uri: "/users", method: .get, headers: [.cookie: signed.cookie]) {
                #expect($0.status == .seeOther)
            }
        }
    }
}
