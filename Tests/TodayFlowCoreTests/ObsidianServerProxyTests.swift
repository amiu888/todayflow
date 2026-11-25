import Foundation
import Testing
@testable import TodayFlowCore

/// Answers every request from a per-test handler and records it.
final class ProxyStubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            recorded.httpBody = data
        }
        Self.requests.append(recorded)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("Obsidian through the TodayFlow server", .serialized)
struct ObsidianServerProxyTests {
    private let settings = ObsidianSettings(
        enabled: true,
        mode: .remote,
        remoteHost: "192.168.1.50",
        remotePort: 27124,
        remoteUseHTTPS: true,
        remoteTransport: .server
    )
    private let proxy = ObsidianServerProxy(
        serverURL: URL(string: "https://nas.example.ts.net:8787")!,
        token: "device-token"
    )

    private func client(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) -> ObsidianRemoteClient {
        ProxyStubProtocol.requests = []
        ProxyStubProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProxyStubProtocol.self]
        return ObsidianRemoteClient(settings: settings, apiKey: "plugin-key", proxy: proxy, configuration: configuration)!
    }

    @Test func writesGoToTheServerWithBothCredentials() async throws {
        let transport = client { _ in (204, Data()) }
        try await transport.write("TodayFlow/Tasks/2026-11/Review Q4 (a1b2c3).md", content: "hello")

        let request = try #require(ProxyStubProtocol.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString
            == "https://nas.example.ts.net:8787/v1/obsidian/vault/TodayFlow/Tasks/2026-11/Review%20Q4%20%28a1b2c3%29.md")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer device-token")
        #expect(request.value(forHTTPHeaderField: "X-Obsidian-Target") == "https://192.168.1.50:27124")
        #expect(request.value(forHTTPHeaderField: "X-Obsidian-Authorization") == "Bearer plugin-key")
        #expect(request.httpBody == Data("hello".utf8))
    }

    @Test func readsListsDeletesAndOpensThroughTheServer() async throws {
        let transport = client { request in
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/v1/obsidian/vault/TodayFlow/Tasks.md"): return (200, Data("# Tasks".utf8))
            case ("GET", "/v1/obsidian/vault/TodayFlow"): return (200, Data(#"{"files":["Tasks.md"]}"#.utf8))
            case ("DELETE", _): return (204, Data())
            case ("POST", "/v1/obsidian/open/TodayFlow/Tasks.md"): return (200, Data())
            default: return (404, Data())
            }
        }
        #expect(try await transport.read("TodayFlow/Tasks.md") == "# Tasks")
        #expect(try await transport.list("TodayFlow") == ["Tasks.md"])
        try await transport.delete("TodayFlow/Old.md")
        try await transport.open("TodayFlow/Tasks.md")
        #expect(try await transport.read("TodayFlow/Missing.md") == nil)
        #expect(ProxyStubProtocol.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer device-token" })
    }

    @Test func serverErrorsBecomeClearMessages() async throws {
        await #expect(throws: ObsidianRemoteError.serverSignIn) {
            try await client { _ in (401, Data()) }.read("TodayFlow/Tasks.md")
        }
        await #expect(throws: ObsidianRemoteError.unauthorized) {
            try await client { _ in (403, Data()) }.read("TodayFlow/Tasks.md")
        }
        let gateway = Data(#"{"error":{"message":"The TodayFlow server could not reach Obsidian at https://192.168.1.50:27124: connection refused"}}"#.utf8)
        await #expect(throws: ObsidianRemoteError.unreachable(
            "The TodayFlow server could not reach Obsidian at https://192.168.1.50:27124: connection refused"
        )) {
            try await client { _ in (502, gateway) }.read("TodayFlow/Tasks.md")
        }
    }

    @Test func verifySpotsAServerWithoutTheProxy() async throws {
        let transport = client { _ in (404, Data()) }
        await #expect(throws: ObsidianRemoteError.tool("The TodayFlow server is too old for the Obsidian proxy. Update the server.")) {
            try await transport.verify()
        }
    }

    @Test func loadsThePairingSavedBySyncSettings() async throws {
        let store = InMemorySettingRepository()
        let keychain = InMemoryKeychainStore()
        #expect(await ObsidianServerProxy.load(settings: store, keychain: keychain) == nil)

        try await store.set(#"{"server":"http://nas.local:8787","deviceId":"d1","deviceName":"Mac","enabled":true,"pairedAt":0}"#, for: SettingKeys.sync)
        #expect(await ObsidianServerProxy.load(settings: store, keychain: keychain) == nil)

        try await keychain.write("device-token", for: KeychainKeys.syncDeviceToken)
        let loaded = await ObsidianServerProxy.load(settings: store, keychain: keychain)
        #expect(loaded == ObsidianServerProxy(serverURL: URL(string: "http://nas.local:8787")!, token: "device-token"))
    }

    @Test func existingConnectionChoicesStillDecode() throws {
        for transport in ["rest", "mcp", "server"] {
            let json = #"{"enabled":true,"mode":"remote","remoteHost":"h","remoteTransport":"\#(transport)"}"#
            let decoded = try JSONDecoder().decode(ObsidianSettings.self, from: Data(json.utf8))
            #expect(decoded.remoteTransport.rawValue == transport)
        }
        let local = try JSONDecoder().decode(ObsidianSettings.self, from: Data(#"{"enabled":true,"vaultPath":"/v"}"#.utf8))
        #expect(local.mode == .local)
        #expect(local.remoteTransport == .rest)
    }

    @Test func directRestClientIsUnchanged() throws {
        let direct = ObsidianSettings(enabled: true, mode: .remote, remoteHost: "192.168.1.50", remotePort: 27124)
        let rest = try #require(ObsidianRemoteClient(settings: direct, apiKey: "k"))
        #expect(rest.url(for: "/vault/TodayFlow/Tasks.md")?.absoluteString
            == "https://192.168.1.50:27124/vault/TodayFlow/Tasks.md")
    }
}
