import Foundation

/// The HTTP seam used by `OpenAICompatibleAssistant` (driver.md §8).
///
/// Production uses `URLSessionAITransport`; tests substitute a recorded/mock
/// transport so every feature and failure mode is exercised without a server.
public protocol AITransport: Sendable {
    /// A non-streaming request (suggestions, breakdowns, plans, model list).
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)

    /// A streaming request. Each element is one line from the response body
    /// (SSE `data:` lines or, for servers that ignore `stream`, one JSON line).
    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<String, Error>
}

/// `URLSession`-backed transport (driver.md §8: URLSession, async/await,
/// Server-Sent Events).
public struct URLSessionAITransport: AITransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        return (data, http)
    }

    public func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
            }
            throw AIError.http(
                status: http.statusCode,
                message: String(decoding: body, as: UTF8.self)
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: AIError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
