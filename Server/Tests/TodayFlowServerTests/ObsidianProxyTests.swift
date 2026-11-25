import AsyncHTTPClient
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing
@testable import TodayFlowServerKit

@Suite("Obsidian proxy target")
struct ObsidianProxyTargetTests {
    @Test func acceptsPlainPluginAddresses() {
        #expect(ObsidianProxy.target(from: "https://192.168.1.50:27124") == "https://192.168.1.50:27124")
        #expect(ObsidianProxy.target(from: "http://studio.local:27123/") == "http://studio.local:27123")
        #expect(ObsidianProxy.target(from: "https://obsidian.tail1234.ts.net") == "https://obsidian.tail1234.ts.net:443")
    }

    @Test func refusesAnythingElse() {
        #expect(ObsidianProxy.target(from: nil) == nil)
        #expect(ObsidianProxy.target(from: "ftp://host:21") == nil)
        #expect(ObsidianProxy.target(from: "https://user:pw@host:27124") == nil)
        #expect(ObsidianProxy.target(from: "https://host:27124/vault/x.md") == nil)
        #expect(ObsidianProxy.target(from: "https://host:27124?x=1") == nil)
        #expect(ObsidianProxy.target(from: "host:27124") == nil)
    }
}

/// A stand-in for the Obsidian Local REST API plugin.
actor FakeObsidian {
    static let key = "plugin-key"
    var notes: [String: String] = ["/vault/TodayFlow/Tasks.md": "# Tasks"]
    var seenPaths: [String] = []
    var opened: [String] = []

    func record(_ path: String) { seenPaths.append(path) }
    func write(_ path: String, _ text: String) { notes[path] = text }
    func delete(_ path: String) { notes[path] = nil }
    func open(_ path: String) { opened.append(path) }

    nonisolated func router() -> Router<BasicRequestContext> {
        let router = Router()
        @Sendable func authorized(_ request: Request) -> Bool {
            request.headers[.authorization] == "Bearer \(Self.key)"
        }
        router.get("/") { request, _ -> Response in
            let body = #"{"status":"OK","service":"Obsidian Local REST API","authenticated":\#(authorized(request))}"#
            return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(string: body)))
        }
        for route in ["vault", "vault/**"] {
            router.get(RouterPath(route)) { request, _ -> Response in
                await self.record(request.uri.path)
                guard authorized(request) else { return Response(status: .unauthorized) }
                if request.uri.path.hasSuffix("/") {
                    let body = #"{"files":["Tasks.md","Daily/"]}"#
                    return Response(status: .ok, headers: [.contentType: "application/json"], body: .init(byteBuffer: ByteBuffer(string: body)))
                }
                guard let text = await self.notes[request.uri.path] else { return Response(status: .notFound) }
                return Response(status: .ok, headers: [.contentType: "text/markdown"], body: .init(byteBuffer: ByteBuffer(string: text)))
            }
        }
        router.put("vault/**") { request, _ -> Response in
            await self.record(request.uri.path)
            guard authorized(request) else { return Response(status: .unauthorized) }
            let body = try await request.body.collect(upTo: 1 << 20)
            await self.write(request.uri.path, String(buffer: body))
            return Response(status: .noContent)
        }
        router.delete("vault/**") { request, _ -> Response in
            guard authorized(request) else { return Response(status: .unauthorized) }
            await self.delete(request.uri.path)
            return Response(status: .noContent)
        }
        router.post("open/**") { request, _ -> Response in
            guard authorized(request) else { return Response(status: .unauthorized) }
            await self.open(request.uri.path)
            return Response(status: .ok)
        }
        return router
    }
}

extension SyncTests {
    /// Runs `body` with a live fake Obsidian and a TodayFlow server whose
    /// proxy points at nothing in particular (devices name the target).
    func withObsidian(
        _ body: @escaping @Sendable (any TestClientProtocol, String, FakeObsidian, String) async throws -> Void
    ) async throws {
        let fake = FakeObsidian()
        let obsidianApp = Application(router: fake.router(), configuration: .init(address: .hostname("127.0.0.1", port: 0)))
        let http = ObsidianProxy.makeHTTPClient()
        try await obsidianApp.test(.live) { obsidian in
            let target = "http://localhost:\(obsidian.port!)"
            try await withServer(configure: { $0.obsidian = ObsidianProxy(client: http) }) { client, store in
                let device = try await device(client, store, user: "alice", name: "Mac")
                try await body(client, device.token, fake, target)
            }
        }
        try await http.shutdown()
    }

    func obsidianHeaders(token: String, target: String, key: String = FakeObsidian.key) -> HTTPFields {
        var headers: HTTPFields = [.authorization: "Bearer \(token)"]
        headers[HTTPField.Name(ObsidianProxy.targetHeader)!] = target
        headers[HTTPField.Name(ObsidianProxy.authorizationHeader)!] = "Bearer \(key)"
        return headers
    }

    @Test func proxyReadsWritesListsDeletesAndOpensNotes() async throws {
        try await withObsidian { client, token, fake, target in
            let headers = obsidianHeaders(token: token, target: target)

            try await client.execute(uri: "/v1/obsidian/status", method: .get, headers: headers) { response in
                #expect(response.status == .ok, "\(target) \(String(buffer: response.body))")
                #expect(String(buffer: response.body).contains(#""authenticated":true"#))
            }
            try await client.execute(uri: "/v1/obsidian/vault/TodayFlow/Tasks.md", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body) == "# Tasks")
            }

            var put = headers
            put[.contentType] = "text/markdown"
            let path = "/v1/obsidian/vault/TodayFlow/Tasks/2026-11/Review%20Q4%20%28a1b2c3%29.md"
            try await client.execute(uri: path, method: .put, headers: put, body: ByteBuffer(string: "hello")) { response in
                #expect(response.status == .noContent)
            }
            #expect(await fake.seenPaths.last == "/vault/TodayFlow/Tasks/2026-11/Review%20Q4%20%28a1b2c3%29.md")
            #expect(await fake.notes["/vault/TodayFlow/Tasks/2026-11/Review%20Q4%20%28a1b2c3%29.md"] == "hello")

            try await client.execute(uri: "/v1/obsidian/vault/TodayFlow/", method: .get, headers: headers) { response in
                #expect(response.status == .ok)
                #expect(String(buffer: response.body).contains("Tasks.md"))
            }
            try await client.execute(uri: path, method: .delete, headers: headers) { response in
                #expect(response.status == .noContent)
            }
            #expect(await fake.notes["/vault/TodayFlow/Tasks/2026-11/Review%20Q4%20%28a1b2c3%29.md"] == nil)

            try await client.execute(uri: "/v1/obsidian/open/TodayFlow/Tasks.md", method: .post, headers: headers) { response in
                #expect(response.status == .ok)
            }
            #expect(await fake.opened == ["/open/TodayFlow/Tasks.md"])

            try await client.execute(uri: "/v1/obsidian/vault/Missing.md", method: .get, headers: headers) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test func proxyNeedsASyncToken() async throws {
        try await withObsidian { client, _, fake, target in
            let headers = obsidianHeaders(token: "not-a-token", target: target)
            try await client.execute(uri: "/v1/obsidian/vault/TodayFlow/Tasks.md", method: .get, headers: headers) { response in
                #expect(response.status == .unauthorized)
            }
            #expect(await fake.seenPaths.isEmpty)
        }
    }

    @Test func wrongObsidianKeyIsForbiddenNotUnauthorized() async throws {
        try await withObsidian { client, token, _, target in
            let headers = obsidianHeaders(token: token, target: target, key: "wrong")
            try await client.execute(uri: "/v1/obsidian/vault/TodayFlow/Tasks.md", method: .get, headers: headers) { response in
                #expect(response.status == .forbidden)
            }
        }
    }

    @Test func badOrUnreachableTargets() async throws {
        try await withObsidian { client, token, _, _ in
            let missing = obsidianHeaders(token: token, target: "not a url")
            try await client.execute(uri: "/v1/obsidian/status", method: .get, headers: missing) { response in
                #expect(response.status == .badRequest)
            }
            // Port 9 (discard) is closed on test machines.
            let closed = obsidianHeaders(token: token, target: "http://127.0.0.1:9")
            try await client.execute(uri: "/v1/obsidian/status", method: .get, headers: closed) { response in
                #expect(response.status == .badGateway)
                #expect(String(buffer: response.body).contains("connection refused"))
            }
        }
    }

    @Test func onlyPluginPathsAreForwarded() async throws {
        try await withObsidian { client, token, _, target in
            let headers = obsidianHeaders(token: token, target: target)
            try await client.execute(uri: "/v1/obsidian/commands/", method: .get, headers: headers) { response in
                #expect(response.status == .notFound)
            }
            try await client.execute(uri: "/v1/obsidian/vault/x.md", method: .post, headers: headers) { response in
                #expect(response.status == .notFound || response.status == .methodNotAllowed)
            }
        }
    }

    @Test func proxyIsOffUnlessConfigured() async throws {
        try await withServer { client, store in
            let device = try await device(client, store, user: "bob", name: "Mac")
            try await client.execute(
                uri: "/v1/obsidian/status", method: .get,
                headers: [.authorization: "Bearer \(device.token)"]
            ) { response in
                #expect(response.status == .notFound)
            }
        }
    }
}
