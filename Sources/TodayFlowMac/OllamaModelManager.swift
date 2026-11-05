import Foundation
import TodayFlowFeatures

/// Small client for the local Ollama server. It only talks to loopback and is
/// used by the optional first-run model download; normal AI calls go through
/// the existing OpenAI-compatible client.
public enum OllamaModelError: LocalizedError, Equatable {
    case notRunning
    case http(status: Int)
    case malformedResponse
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama isn’t running. Open the Ollama app and try again."
        case .http(let status):
            return "Ollama returned HTTP \(status)."
        case .malformedResponse:
            return "Ollama sent an unreadable response."
        case .server(let message):
            return message
        }
    }
}

public final class OllamaModelManager: LocalModelInstaller, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func isRunning() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func installedModelNames() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 4
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OllamaModelError.malformedResponse
        }
        guard http.statusCode == 200 else {
            throw OllamaModelError.http(status: http.statusCode)
        }
        guard let tags = try? JSONDecoder().decode(TagsResponse.self, from: data) else {
            throw OllamaModelError.malformedResponse
        }
        return tags.models.map(\.name)
    }

    public func download(
        _ model: LocalAIModel
    ) -> AsyncThrowingStream<LocalModelDownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let decoder = JSONDecoder()
                do {
                    var request = URLRequest(
                        url: baseURL.appendingPathComponent("api/pull")
                    )
                    request.httpMethod = "POST"
                    request.timeoutInterval = 3_600
                    request.setValue(
                        "application/json",
                        forHTTPHeaderField: "Content-Type"
                    )
                    request.httpBody = try JSONEncoder().encode(
                        PullRequest(name: model.ollamaName, stream: true)
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OllamaModelError.malformedResponse
                    }
                    guard http.statusCode == 200 else {
                        throw OllamaModelError.http(status: http.statusCode)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let event = try? decoder.decode(PullEvent.self, from: data)
                        else { continue }
                        if let message = event.error, !message.isEmpty {
                            throw OllamaModelError.server(message)
                        }
                        continuation.yield(event.progress)
                        if event.status == "success" { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Wire types

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }
        let models: [Model]
    }

    private struct PullRequest: Encodable {
        let name: String
        let stream: Bool
    }

    private struct PullEvent: Decodable {
        let status: String?
        let total: Int64?
        let completed: Int64?
        let error: String?

        var progress: LocalModelDownloadProgress {
            let status = status ?? ""
            let phase: LocalModelDownloadProgress.Phase
            switch status {
            case "pulling manifest", "pulling":
                phase = .preparing
            case "downloading":
                phase = .downloading
            case "verifying sha256 digest":
                phase = .verifying
            case "writing manifest", "removing any unused layers":
                phase = .writing
            case "success":
                phase = .done
            default:
                phase = .preparing
            }
            return LocalModelDownloadProgress(
                phase: phase,
                completedBytes: completed ?? 0,
                totalBytes: total ?? 0,
                status: status
            )
        }
    }
}
