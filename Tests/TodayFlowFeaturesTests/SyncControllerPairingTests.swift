import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowFeatures

/// A TodayFlow server in memory, reached through URLSession: users with a
/// pairing code, devices with a token that can be signed out.
final class StubServer: URLProtocol, @unchecked Sendable {
    struct State {
        /// code → user name
        var codes: [String: String] = [:]
        /// token → user name (signed-out tokens are removed)
        var tokens: [String: String] = [:]
        /// Hosts that answer; others time out.
        var hosts: Set<String> = []
        var paired = 0
    }

    nonisolated(unsafe) private static var states: [String: State] = [:]
    private static let lock = NSLock()

    /// Each test uses its own key so tests can run side by side.
    static func with<T>(_ key: String, _ body: (inout State) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        var state = states[key] ?? State()
        defer { states[key] = state }
        return body(&state)
    }

    static func session(key: String) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        configuration.httpAdditionalHeaders = ["X-Stub": key]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Stub") ?? ""
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        let body = Self.body(of: request)

        let answer: (Int, Any)? = Self.with(key) { state in
            guard state.hosts.contains(host) else { return nil }
            switch path {
            case "/v1/pair":
                let code = (body["pairingCode"] as? String ?? "").lowercased().filter(\.isHexDigit)
                guard let user = state.codes[code] else { return (401, ["error": ["message": "Unknown code"]]) }
                state.paired += 1
                let newToken = "token-\(state.paired)"
                state.tokens[newToken] = user
                return (200, ["deviceId": "device-\(state.paired)", "token": newToken, "userName": user])
            case "/v1/status":
                guard let token, let user = state.tokens[token] else {
                    return (401, ["error": ["message": "Sign-in token missing, unknown, or revoked."]])
                }
                return (200, ["userId": "id-\(user)", "userName": user, "records": 0, "deviceId": "d"])
            default:
                return (404, ["error": ["message": "Not found"]])
            }
        }
        guard let (status, json) = answer else {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: json)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func body(of request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

/// Changing the server address, being signed out on the server, and pairing
/// again with a new code: what happened to the work Mac and the iPhone.
@MainActor
struct SyncControllerPairingTests {
    let key = UUID().uuidString
    let codeA = "aaaaaa-bbbbbb-cccccc-dddddd"
    let codeB = "111111-222222-333333-444444"
    let home = "http://nas.local:8787"
    let away = "https://sync.example.org"

    struct Device {
        let controller: SyncController
        let settings: InMemorySettingRepository
        let keychain: InMemoryKeychainStore
    }

    func makeDevice(settings: InMemorySettingRepository = InMemorySettingRepository(),
                    keychain: InMemoryKeychainStore = InMemoryKeychainStore()) throws -> Device {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-pair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dbURL = folder.appendingPathComponent("todayflow.sqlite")
        let controller = SyncController(
            queue: try TodayFlowDatabase.make(at: dbURL), databaseURL: dbURL,
            settings: settings, keychain: keychain,
            filesDirectory: folder.appendingPathComponent("Attachments"),
            session: StubServer.session(key: key)
        )
        return Device(controller: controller, settings: settings, keychain: keychain)
    }

    /// One server reachable at a home and a public address, with user Afonso.
    func serverWithAfonso() {
        StubServer.with(key) { state in
            state.hosts = ["nas.local", "sync.example.org"]
            state.codes = [codeA.filter(\.isHexDigit): "Afonso"]
        }
    }

    // MARK: - Change… keeps the pairing

    @Test func changingTheAddress_keepsThePairing_andIsRemembered() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        #expect(await mac.controller.pair(server: home, code: codeA) == nil)
        let token = await mac.keychain.read(SyncController.tokenKey)

        #expect(await mac.controller.changeServer(to: away) == nil)
        #expect(mac.controller.snapshot.serverAddress == away)
        #expect(mac.controller.snapshot.userName == "Afonso")
        #expect(mac.controller.snapshot.addressError == nil)
        #expect(await mac.keychain.read(SyncController.tokenKey) == token) // not paired again
        #expect(StubServer.with(key) { $0.paired } == 1)

        let restarted = try makeDevice(settings: mac.settings, keychain: mac.keychain)
        await restarted.controller.start()
        #expect(restarted.controller.snapshot.serverAddress == away)
    }

    @Test func changingToAnAddressThatDoesNotAnswer_keepsTheOldOne() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        let error = await mac.controller.changeServer(to: "https://nowhere.example.org")
        #expect(error != nil)
        #expect(mac.controller.snapshot.serverAddress == home)
        #expect(mac.controller.snapshot.addressError == error)
    }

    @Test func changingToPlainHttpOutsideHome_isRefused() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        let error = await mac.controller.changeServer(to: "http://sync.example.org")
        #expect(error?.contains("https://") == true)
        #expect(mac.controller.snapshot.serverAddress == home)
    }

    @Test func changingToAServerThatKnowsThisTokenAsAnotherUser_isRefused() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        StubServer.with(key) { state in
            for token in state.tokens.keys { state.tokens[token] = "test" }
        }
        let error = await mac.controller.changeServer(to: away)
        #expect(error?.contains("test") == true)
        #expect(mac.controller.snapshot.serverAddress == home)
    }

    // MARK: - Signed out on the server (the work Mac)

    @Test func signedOutOnTheServer_changeExplainsIt_andKeepsTheAddress() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        StubServer.with(key) { $0.tokens.removeAll() } // admin page ▸ Devices ▸ Sign out

        let error = await mac.controller.changeServer(to: away)
        #expect(error?.contains("signed out") == true)
        #expect(error?.contains("pair again") == true)
        #expect(mac.controller.snapshot.serverAddress == home)
    }

    @Test func afterPairingAgain_theOldAddressErrorIsGone() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        StubServer.with(key) { $0.tokens.removeAll() }
        _ = await mac.controller.changeServer(to: away)
        #expect(mac.controller.snapshot.addressError != nil)

        await mac.controller.unpair()
        #expect(mac.controller.snapshot.addressError == nil)
        #expect(await mac.controller.pair(server: away, code: codeA) == nil)
        #expect(mac.controller.snapshot.isPaired)
        #expect(mac.controller.snapshot.serverAddress == away)
        #expect(mac.controller.snapshot.addressError == nil)
    }

    // MARK: - A new code (the iPhone)

    @Test func pairingAgainWithANewCode_works_andTheOldCodeStops() async throws {
        serverWithAfonso()
        let phone = try makeDevice()
        _ = await phone.controller.pair(server: away, code: codeA)
        let oldToken = await phone.keychain.read(SyncController.tokenKey)
        await phone.controller.unpair()
        #expect(await phone.keychain.read(SyncController.tokenKey) == nil)

        // Admin page ▸ Users ▸ Afonso ▸ New code.
        StubServer.with(key) { $0.codes = [codeB.filter(\.isHexDigit): "Afonso"] }
        #expect(await phone.controller.pair(server: away, code: codeA) != nil)
        #expect(!phone.controller.snapshot.isPaired)

        // Typed in capitals with spaces, the way the iPhone keyboard does.
        let again = await phone.controller.pair(server: away, code: " " + codeB.uppercased())
        #expect(again == nil, "\(again ?? "")")
        #expect(phone.controller.snapshot.isPaired)
        #expect(phone.controller.snapshot.userName == "Afonso")
        let newToken = await phone.keychain.read(SyncController.tokenKey)
        #expect(newToken != nil && newToken != oldToken)
    }

    @Test func aNewCode_doesNotSignOutDevicesAlreadyPaired() async throws {
        serverWithAfonso()
        let mac = try makeDevice()
        _ = await mac.controller.pair(server: home, code: codeA)
        StubServer.with(key) { $0.codes = [codeB.filter(\.isHexDigit): "Afonso"] }
        // Still accepted: Change… only works when the server knows this Mac.
        #expect(await mac.controller.changeServer(to: away) == nil)
    }
}
