import Foundation
import TodayFlowCore

/// Everything the OpenAI-compatible client needs (driver.md §8).
///
/// The API key is copied from the Keychain-backed `AIEndpointSettings` at
/// construction time; it is never written into a request body or log.
public struct AIConfiguration: Hashable, Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var model: String
    public var timeout: TimeInterval
    /// Privacy toggle: false sends only titles and metadata, never attachment
    /// text (driver.md §8 guardrails).
    public var sendAttachmentText: Bool

    public init(
        baseURL: URL,
        apiKey: String = "",
        model: String,
        timeout: TimeInterval = 20,
        sendAttachmentText: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeout = min(max(timeout, 1), 120)
        self.sendAttachmentText = sendAttachmentText
    }

    /// Builds the client configuration from the stored settings.
    public init(settings: AIEndpointSettings) throws {
        guard settings.enabled else { throw AIError.disabled }
        guard let baseURL = URL(string: settings.baseURL),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              baseURL.host != nil
        else {
            throw AIError.invalidConfiguration("The base URL must be an http(s) URL.")
        }
        guard !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidConfiguration("Choose a model.")
        }
        self.init(
            baseURL: baseURL,
            apiKey: settings.apiKey,
            model: settings.model,
            timeout: settings.timeoutSeconds,
            sendAttachmentText: settings.sendAttachmentText
        )
    }

    /// `POST {baseURL}/chat/completions`.
    public var chatCompletionsURL: URL? {
        baseURL.appendingPathComponent("chat/completions")
    }

    /// `GET {baseURL}/models`.
    public var modelsURL: URL? {
        baseURL.appendingPathComponent("models")
    }
}

/// Errors surfaced to the UI. Every case is safe to show to the user.
public enum AIError: Error, Sendable, Equatable, LocalizedError {
    case disabled
    case invalidConfiguration(String)
    case invalidResponse
    case http(status: Int, message: String)
    case malformedResponse(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "AI is turned off."
        case .invalidConfiguration(let message):
            return message
        case .invalidResponse:
            return "The AI endpoint returned an unreadable response."
        case .http(let status, let message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "The AI endpoint returned HTTP \(status)."
                : "The AI endpoint returned HTTP \(status): \(detail)"
        case .malformedResponse(let detail):
            return "The AI response wasn’t valid JSON: \(detail)"
        case .transport(let message):
            return "Couldn’t reach the AI endpoint: \(message)"
        }
    }
}

/// A redacted description of one outgoing request, for the "What was sent"
/// disclosure (driver.md §8 guardrails). The API key is never part of it.
public struct AIRequestInfo: Hashable, Sendable {
    public let feature: String
    public let url: URL
    public let model: String
    public let body: String

    public init(feature: String, url: URL, model: String, body: String) {
        self.feature = feature
        self.url = url
        self.model = model
        self.body = body
    }
}
