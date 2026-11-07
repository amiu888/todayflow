import Foundation
import TodayFlowCore
import TodayFlowFeatures

/// Probes the well-known localhost ports used by common local AI software.
/// Loopback only; no external network traffic and no process launching.
public final class LocalAIDiscovery: LocalAIDiscovering, @unchecked Sendable {
    private struct Endpoint {
        let name: String
        let baseURL: URL
        let provider: AIEndpointSettings.Provider
    }

    private static let endpoints: [Endpoint] = [
        Endpoint(name: "GPU Buddy / llama.cpp", baseURL: URL(string: "http://127.0.0.1:8080/v1")!, provider: .gpuBuddy),
        Endpoint(name: "Ollama", baseURL: URL(string: "http://127.0.0.1:11434/v1")!, provider: .ollama),
        Endpoint(name: "LM Studio", baseURL: URL(string: "http://127.0.0.1:1234/v1")!, provider: .lmStudio),
        Endpoint(name: "vLLM", baseURL: URL(string: "http://127.0.0.1:8000/v1")!, provider: .custom),
        Endpoint(name: "text-generation-webui", baseURL: URL(string: "http://127.0.0.1:5000/v1")!, provider: .custom),
        Endpoint(name: "Jan", baseURL: URL(string: "http://127.0.0.1:1337/v1")!, provider: .custom),
    ]

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func scan() async -> [LocalAICandidate] {
        await scan(customPort: nil)
    }

    public func scan(customPort: Int?) async -> [LocalAICandidate] {
        var endpoints = Self.endpoints
        if let customPort, (1...65_535).contains(customPort),
           let url = URL(string: "http://127.0.0.1:\(customPort)/v1")
        {
            // Replace the standard entry for this port so the result names the
            // port the user actually asked for instead of guessing the product.
            endpoints.removeAll { $0.baseURL == url }
            endpoints.append(Endpoint(
                name: "Local server (port \(customPort))",
                baseURL: url,
                provider: .custom
            ))
        }
        return await withTaskGroup(of: LocalAICandidate?.self) { group in
            for endpoint in endpoints {
                group.addTask { await self.probe(endpoint) }
            }
            var found: [LocalAICandidate] = []
            for await candidate in group {
                if let candidate { found.append(candidate) }
            }
            return found.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    private func probe(_ endpoint: Endpoint) async -> LocalAICandidate? {
        var models = await openAIModels(endpoint.baseURL)
        if models.isEmpty, endpoint.provider == .ollama {
            models = await ollamaModels(endpoint.baseURL)
        }
        let unique = Array(Set(models)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        guard !unique.isEmpty else { return nil }
        return LocalAICandidate(
            id: endpoint.baseURL.absoluteString,
            name: endpoint.name,
            baseURL: endpoint.baseURL,
            provider: endpoint.provider,
            models: unique
        )
    }

    private func openAIModels(_ baseURL: URL) async -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 1.5
        request.setValue("TodayFlow/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data)
        else { return [] }
        return decoded.data.map(\.id).filter { !$0.isEmpty }
    }

    private func ollamaModels(_ baseURL: URL) async -> [String] {
        // baseURL ends in /v1; Ollama's native tags endpoint is /api/tags.
        let root = baseURL.deletingLastPathComponent()
        var request = URLRequest(url: root.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.5
        request.setValue("TodayFlow/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data)
        else { return [] }
        return decoded.models.map(\.name).filter { !$0.isEmpty }
    }

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }
}
