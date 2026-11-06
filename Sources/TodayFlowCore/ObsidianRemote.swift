import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum ObsidianRemoteError: LocalizedError, Equatable {
    case invalidAddress
    case unauthorized
    case unreachable(String)
    case server(Int)
    case tool(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "The Obsidian server address is invalid."
        case .unauthorized:
            "Obsidian rejected the API key."
        case .unreachable(let message):
            "Could not reach Obsidian: \(message)"
        case .server(let status):
            "Obsidian returned HTTP \(status)."
        case .tool(let message):
            message
        }
    }
}

/// The operations TodayFlow needs from a remote Obsidian plugin. REST and MCP
/// are interchangeable transports over the same Local REST API plugin.
public protocol ObsidianRemoteTransport: Sendable {
    func verify() async throws
    func read(_ path: String) async throws -> String?
    func write(_ path: String, content: String) async throws
    func open(_ path: String) async throws
}

/// Talks to the Obsidian Local REST API plugin on another machine.
/// HTTPS accepts the plugin's self-signed certificate for this connection.
public final class ObsidianRemoteClient: ObsidianRemoteTransport, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let trust: ObsidianTrustDelegate
    private let session: URLSession

    public init?(settings: ObsidianSettings, apiKey: String) {
        guard settings.mode == .remote,
              let baseURL = settings.remoteBaseURL
        else { return nil }
        self.baseURL = baseURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let trust = ObsidianTrustDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        self.trust = trust
        self.session = URLSession(
            configuration: configuration,
            delegate: trust,
            delegateQueue: nil
        )
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// Verifies both connectivity and the API key.
    public func verify() async throws {
        let (data, response) = try await send(method: "GET", path: "/vault/")
        guard response.statusCode == 200 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ObsidianRemoteError.unauthorized
            }
            throw ObsidianRemoteError.server(response.statusCode)
        }
        _ = data
    }

    public func read(_ path: String) async throws -> String? {
        let (data, response) = try await send(
            method: "GET",
            path: "/vault/\(path)",
            accept: "text/markdown"
        )
        if response.statusCode == 404 { return nil }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ObsidianRemoteError.unauthorized
        }
        guard response.statusCode == 200 else {
            throw ObsidianRemoteError.server(response.statusCode)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ObsidianRemoteError.server(response.statusCode)
        }
        return text
    }

    public func write(_ path: String, content: String) async throws {
        let body = Data(content.utf8)
        let (_, response) = try await send(
            method: "PUT",
            path: "/vault/\(path)",
            body: body,
            contentType: "text/markdown"
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ObsidianRemoteError.unauthorized
        }
        guard (200...299).contains(response.statusCode) else {
            throw ObsidianRemoteError.server(response.statusCode)
        }
    }

    public func open(_ path: String) async throws {
        let (_, response) = try await send(
            method: "POST",
            path: "/open/\(path)"
        )
        if response.statusCode == 401 || response.statusCode == 403 {
            throw ObsidianRemoteError.unauthorized
        }
        guard (200...299).contains(response.statusCode) else {
            throw ObsidianRemoteError.server(response.statusCode)
        }
    }

    private func send(
        method: String,
        path: String,
        body: Data? = nil,
        contentType: String? = nil,
        accept: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = url(for: path) else {
            throw ObsidianRemoteError.invalidAddress
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ObsidianRemoteError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ObsidianRemoteError.unreachable("No HTTP response.")
        }
        return (data, http)
    }

    func url(for path: String) -> URL? {
        var clean = path
        while clean.hasPrefix("/") { clean.removeFirst() }
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-._~"))
        let encoded = clean
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(withAllowedCharacters: allowed)
                    ?? String(segment)
            }
            .joined(separator: "/")
        let base = baseURL.absoluteString.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return URL(string: "\(base)/\(encoded)")
    }
}

/// Accepts the locally generated certificate used by the Obsidian plugin.
/// This is scoped to the remote Obsidian URLSession, not the whole app.
final class ObsidianTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

public struct DiscoveredObsidianServer: Identifiable, Hashable, Sendable {
    public let host: String
    public let port: Int
    public let useHTTPS: Bool

    public var id: String {
        "\(useHTTPS ? "https" : "http")://\(host):\(port)"
    }

    public var displayName: String {
        "\(host):\(port) · \(useHTTPS ? "HTTPS" : "HTTP")"
    }

    public init(host: String, port: Int, useHTTPS: Bool) {
        self.host = host
        self.port = port
        self.useHTTPS = useHTTPS
    }
}

/// Finds Obsidian Local REST API servers on the current IPv4 LAN by probing
/// the plugin's two standard ports. The API key still has to be copied once
/// from the remote Obsidian plugin settings.
public enum ObsidianLANDiscovery {
    public static let httpPort = 27123
    public static let httpsPort = 27124

    public static func scan(timeout: TimeInterval = 0.55) async -> [DiscoveredObsidianServer] {
        let hosts = candidateHosts()
        let trust = ObsidianTrustDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 0.5
        configuration.waitsForConnectivity = false
        let session = URLSession(
            configuration: configuration,
            delegate: trust,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var discovered: [DiscoveredObsidianServer] = []
        for chunk in hosts.chunked(into: 64) {
            let found = await withTaskGroup(
                of: DiscoveredObsidianServer?.self
            ) { group in
                for host in chunk {
                    for probe in [
                        (httpPort, false),
                        (httpsPort, true),
                    ] {
                        group.addTask {
                            await probeServer(
                                host: host,
                                port: probe.0,
                                useHTTPS: probe.1,
                                session: session
                            )
                        }
                    }
                }
                var results: [DiscoveredObsidianServer] = []
                for await result in group {
                    if let result { results.append(result) }
                }
                return results
            }
            discovered.append(contentsOf: found)
        }

        return discovered.sorted {
            ($0.host, $0.port) < ($1.host, $1.port)
        }
    }

    static func probeServer(
        host: String,
        port: Int,
        useHTTPS: Bool,
        session: URLSession
    ) async -> DiscoveredObsidianServer? {
        let scheme = useHTTPS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.55
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              isObsidianStatus(data)
        else { return nil }
        return DiscoveredObsidianServer(
            host: host,
            port: port,
            useHTTPS: useHTTPS
        )
    }

    static func isObsidianStatus(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return object["status"] as? String == "OK"
            && object["authenticated"] is Bool
    }

    static func candidateHosts() -> [String] {
        var candidates: Set<String> = ["127.0.0.1"]
        #if canImport(Darwin)
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return candidates.sorted() }
        defer { freeifaddrs(head) }

        var cursor = head
        while let interface = cursor {
            defer { cursor = interface.pointee.ifa_next }
            let flags = Int32(interface.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  let mask = interface.pointee.ifa_netmask,
                  let ip = ipv4String(address),
                  let netmask = ipv4String(mask)
            else { continue }
            candidates.formUnion(hosts(inIPv4: ip, netmask: netmask))
        }
        #endif
        return candidates.sorted()
    }

    /// Enumerates the usable hosts in an IPv4 subnet. Very large subnets are
    /// limited to the local /24 so a scan stays quick.
    public static func hosts(inIPv4 ip: String, netmask: String) -> [String] {
        guard let ipValue = ipv4Value(ip),
              let maskValue = ipv4Value(netmask)
        else { return [] }
        let prefix = maskValue.nonzeroBitCount
        guard prefix >= 8 else { return [] }

        let network: UInt32
        let broadcast: UInt32
        if prefix >= 24 {
            network = ipValue & maskValue
            broadcast = network | ~maskValue
        } else {
            network = ipValue & 0xFFFF_FF00
            broadcast = network | 0x0000_00FF
        }
        guard broadcast > network + 1 else { return [] }
        let first = network + 1
        let last = broadcast - 1
        let count = Int(last - first) + 1
        guard count > 0 else { return [] }
        let limited = min(count, 254)
        return (0..<limited).map { dotted(first + UInt32($0)) }
    }

    private static func ipv4String(_ address: UnsafePointer<sockaddr>) -> String? {
        var text = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(address.pointee.sa_len)
        guard getnameinfo(
            address,
            length,
            &text,
            socklen_t(text.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else { return nil }
        let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func ipv4Value(_ text: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, text, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    private static func dotted(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 1 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
