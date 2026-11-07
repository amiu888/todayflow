import Foundation

/// Talks to the Local REST API plugin's MCP endpoint.
///
/// Uses the modern stateless MCP revision (`2026-07-28`), so each tools/call
/// is a single JSON-RPC POST with no session handshake. The plugin exposes the
/// same vault operations as its REST API.
public final class ObsidianMCPClient: ObsidianRemoteTransport, @unchecked Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let trust: ObsidianTrustDelegate
    private let session: URLSession

    private static let protocolVersion = "2026-07-28"
    private static let clientName = "TodayFlow"

    public init?(settings: ObsidianSettings, apiKey: String) {
        guard settings.mode == .remote,
              let baseURL = settings.remoteBaseURL
        else { return nil }
        self.baseURL = baseURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let trust = ObsidianTrustDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
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

    public func verify() async throws {
        _ = try await call(method: "tools/list")
    }

    public func list(_ path: String) async throws -> [String] {
        let result = try await call(
            method: "tools/call",
            tool: "vault_list",
            arguments: ["path": path]
        )
        try checkToolResult(result)
        guard let text = textContent(result),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = object["files"] as? [String]
        else {
            throw ObsidianRemoteError.tool("MCP returned an unreadable folder listing.")
        }
        return files
    }

    public func read(_ path: String) async throws -> String? {
        let result = try await call(
            method: "tools/call",
            tool: "vault_read",
            arguments: ["path": path]
        )
        if result["isError"] as? Bool == true {
            let message = textContent(result) ?? ""
            let lowered = message.lowercased()
            if lowered.contains("not found")
                || lowered.contains("does not exist")
                || lowered.contains("no such file")
            {
                return nil
            }
            throw ObsidianRemoteError.tool(message)
        }
        guard let text = textContent(result),
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? String
        else {
            throw ObsidianRemoteError.tool("MCP returned an unreadable note.")
        }
        return content
    }

    public func write(_ path: String, content: String) async throws {
        let result = try await call(
            method: "tools/call",
            tool: "vault_write",
            arguments: ["path": path, "content": content]
        )
        try checkToolResult(result)
    }

    public func open(_ path: String) async throws {
        let result = try await call(
            method: "tools/call",
            tool: "open_file",
            arguments: ["path": path]
        )
        try checkToolResult(result)
    }

    // MARK: JSON-RPC

    private func call(
        method: String,
        tool: String? = nil,
        arguments: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL.absoluteString + "/mcp/") else {
            throw ObsidianRemoteError.invalidAddress
        }

        var params: [String: Any] = [
            "_meta": [
                "io.modelcontextprotocol/protocolVersion": Self.protocolVersion,
                "io.modelcontextprotocol/clientInfo": [
                    "name": Self.clientName,
                    "version": "1.9.21",
                ],
                "io.modelcontextprotocol/clientCapabilities": [:],
            ],
        ]
        if let tool {
            params["name"] = tool
            params["arguments"] = arguments ?? [:]
        }

        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": Int.random(in: 1...Int.max),
            "method": method,
            "params": params,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "application/json, text/event-stream",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            Self.protocolVersion,
            forHTTPHeaderField: "MCP-Protocol-Version"
        )
        request.setValue(method, forHTTPHeaderField: "Mcp-Method")
        if let tool {
            request.setValue(tool, forHTTPHeaderField: "Mcp-Name")
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
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ObsidianRemoteError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw ObsidianRemoteError.server(http.statusCode)
        }

        let envelope = try decodeEnvelope(data)
        if let error = envelope["error"] as? [String: Any] {
            throw ObsidianRemoteError.tool(
                error["message"] as? String ?? "MCP request failed."
            )
        }
        guard let result = envelope["result"] as? [String: Any] else {
            throw ObsidianRemoteError.tool("MCP returned no result.")
        }
        return result
    }

    private func decodeEnvelope(_ data: Data) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        // Streamable HTTP may answer with Server-Sent Events.
        guard let text = String(data: data, encoding: .utf8) else {
            throw ObsidianRemoteError.tool("MCP returned unreadable data.")
        }
        let payloads = text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("data:") else { return nil }
                return String(trimmed.dropFirst(5))
                    .trimmingCharacters(in: .whitespaces)
            }
        for payload in payloads.reversed() {
            guard let payloadData = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData)
                    as? [String: Any]
            else { continue }
            return object
        }
        throw ObsidianRemoteError.tool("MCP returned an unexpected response.")
    }

    private func textContent(_ result: [String: Any]) -> String? {
        (result["content"] as? [[String: Any]])?
            .first?["text"] as? String
    }

    private func checkToolResult(_ result: [String: Any]) throws {
        guard result["isError"] as? Bool == true else { return }
        throw ObsidianRemoteError.tool(
            textContent(result) ?? "The Obsidian MCP tool failed."
        )
    }
}
