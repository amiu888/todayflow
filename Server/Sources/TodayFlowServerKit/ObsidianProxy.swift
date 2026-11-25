import AsyncHTTPClient
import Foundation
import Hummingbird
import NIOCore
import NIOHTTP1
import NIOSSL
import HTTPTypes

/// Forwards a signed-in device's requests to the Obsidian Local REST API
/// plugin, so a Mac away from home can reach an Obsidian that only the
/// server can see (same LAN, or the server's Tailscale network).
///
///     GET    /v1/obsidian/status            → GET /          (plugin status)
///     GET    /v1/obsidian/vault/{path…}     → GET /vault/…   (read a note, list a folder)
///     PUT    /v1/obsidian/vault/{path…}     → PUT /vault/…   (write a note)
///     DELETE /v1/obsidian/vault/{path…}     → DELETE /vault/…
///     POST   /v1/obsidian/open/{path…}      → POST /open/…   (show a note in Obsidian)
///
/// The device names the Obsidian address and key on every request:
///
///     X-Obsidian-Target:        https://192.168.1.50:27124
///     X-Obsidian-Authorization: Bearer <plugin API key>
///
/// Nothing is stored on the server. Only these plugin paths are forwarded,
/// and only for devices with a valid sync token.
public struct ObsidianProxy: Sendable {
    public static let targetHeader = "X-Obsidian-Target"
    public static let authorizationHeader = "X-Obsidian-Authorization"

    let client: HTTPClient
    /// Largest note accepted from the device.
    public var maxRequestBytes = 16 * 1024 * 1024
    /// Largest answer accepted from Obsidian.
    public var maxResponseBytes = 64 * 1024 * 1024
    public var timeout: TimeAmount = .seconds(15)

    /// `client` should accept the plugin's self-signed certificate; see
    /// `makeHTTPClient()`.
    public init(client: HTTPClient) {
        self.client = client
    }

    /// An HTTP client for the plugin. The plugin serves HTTPS with a
    /// certificate it generated itself, so certificates are not verified;
    /// the API key is what protects the vault.
    public static func makeHTTPClient() -> HTTPClient {
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .none
        var configuration = HTTPClient.Configuration(tlsConfiguration: tls)
        configuration.timeout = .init(connect: .seconds(5), read: .seconds(15))
        configuration.redirectConfiguration = .disallow
        return HTTPClient(eventLoopGroupProvider: .singleton, configuration: configuration)
    }

    /// The plugin's base URL from the target header, or nil when it is not
    /// a plain `http(s)://host:port`.
    static func target(from header: String?) -> String? {
        guard let header,
              let components = URLComponents(string: header.trimmingCharacters(in: .whitespaces)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return nil }
        let port = components.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65_535).contains(port) else { return nil }
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(hostPart):\(port)"
    }

    /// Forwards one request. `upstreamPath` starts with "/" and is already
    /// percent-encoded, exactly as the device sent it.
    func forward(
        _ request: Request,
        method: HTTPMethod,
        upstreamPath: String
    ) async throws -> Response {
        guard let base = Self.target(from: request.headers[HTTPField.Name(Self.targetHeader)!]) else {
            throw HTTPError(.badRequest, message: "\(Self.targetHeader) must be http(s)://host:port.")
        }
        var upstream = HTTPClientRequest(url: base + upstreamPath)
        upstream.method = method
        if let key = request.headers[HTTPField.Name(Self.authorizationHeader)!] {
            upstream.headers.add(name: "Authorization", value: key)
        }
        if let type = request.headers[.contentType] {
            upstream.headers.add(name: "Content-Type", value: type)
        }
        if let accept = request.headers[.accept] {
            upstream.headers.add(name: "Accept", value: accept)
        }
        if method == .PUT || method == .POST {
            let body: ByteBuffer
            do {
                body = try await request.body.collect(upTo: maxRequestBytes)
            } catch {
                throw HTTPError(.contentTooLarge, message: "Notes are limited to \(maxRequestBytes / 1_048_576) MB.")
            }
            upstream.body = .bytes(body)
        }

        let answer: HTTPClientResponse
        let data: ByteBuffer
        do {
            answer = try await client.execute(upstream, timeout: timeout)
            data = try await answer.body.collect(upTo: maxResponseBytes)
        } catch {
            throw HTTPError(
                .badGateway,
                message: "The TodayFlow server could not reach Obsidian at \(base): \(Self.describe(error))."
            )
        }

        // 401 from this server always means the device's sync token; a key
        // Obsidian rejects is passed on as 403.
        if answer.status == .unauthorized || answer.status == .forbidden {
            throw HTTPError(.forbidden, message: "Obsidian rejected the API key.")
        }
        var headers = HTTPFields()
        if let type = answer.headers.first(name: "Content-Type") {
            headers[.contentType] = type
        }
        return Response(
            status: HTTPResponse.Status(code: Int(answer.status.code)),
            headers: headers,
            body: ResponseBody(byteBuffer: data)
        )
    }
}

extension ObsidianProxy {
    /// A short, readable reason for a failed request to the plugin.
    static func describe(_ error: any Error) -> String {
        if let client = error as? HTTPClientError {
            if client == .connectTimeout || client == .deadlineExceeded || client == .readTimeout {
                return "it did not answer in time"
            }
            if client == .remoteConnectionClosed { return "it closed the connection" }
        }
        let text = String(describing: error)
        if text.contains("rawValue: 61") || text.localizedCaseInsensitiveContains("refused") {
            return "connection refused (is Obsidian running with Local REST API on that port?)"
        }
        if text.contains("rawValue: 65") || text.contains("rawValue: 51") { return "no route to that address" }
        if text.contains("rawValue: 60") { return "it did not answer in time" }
        if text.localizedCaseInsensitiveContains("lookup") || text.contains("NXDOMAIN") {
            return "the server could not look up that host name"
        }
        if text.localizedCaseInsensitiveContains("ssl") || text.localizedCaseInsensitiveContains("tls") {
            return "the secure connection failed (try HTTPS on 27124 or HTTP on 27123)"
        }
        return text
    }

    /// Adds the proxy routes. `caller` checks the sync token.
    func register(
        on router: Router<BasicRequestContext>,
        caller: @escaping @Sendable (Request) async throws -> Store.Caller
    ) {
        let prefix = "/v1/obsidian"

        @Sendable func path(_ request: Request) -> String {
            var path = request.uri.path
            if path.hasPrefix(prefix) { path.removeFirst(prefix.count) }
            if let query = request.uri.query, !query.isEmpty { path += "?" + query }
            return path
        }

        router.get("v1/obsidian/status") { request, _ -> Response in
            _ = try await caller(request)
            return try await forward(request, method: .GET, upstreamPath: "/")
        }
        for route in ["v1/obsidian/vault", "v1/obsidian/vault/**"] {
            router.get(RouterPath(route)) { request, _ -> Response in
                _ = try await caller(request)
                return try await forward(request, method: .GET, upstreamPath: path(request))
            }
        }
        router.put("v1/obsidian/vault/**") { request, _ -> Response in
            _ = try await caller(request)
            return try await forward(request, method: .PUT, upstreamPath: path(request))
        }
        router.delete("v1/obsidian/vault/**") { request, _ -> Response in
            _ = try await caller(request)
            return try await forward(request, method: .DELETE, upstreamPath: path(request))
        }
        router.post("v1/obsidian/open/**") { request, _ -> Response in
            _ = try await caller(request)
            return try await forward(request, method: .POST, upstreamPath: path(request))
        }
    }
}
