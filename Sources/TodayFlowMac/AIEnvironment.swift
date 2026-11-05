#if canImport(AppKit)
import Foundation
import TodayFlowAI
import TodayFlowCore

/// Thread-safe holder for the last outgoing AI request, used by the
/// "What was sent" disclosure (driver.md §8 guardrails).
public final class AIRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var request: AIRequestInfo?

    public init() {}

    func record(_ info: AIRequestInfo) {
        lock.lock()
        request = info
        lock.unlock()
    }

    public var last: AIRequestInfo? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

/// Builds AI clients from the live Settings + Keychain state (driver.md §8).
///
/// The client is recreated on demand so changing the endpoint, model, key, or
/// feature toggles in Settings takes effect immediately — no app restart.
/// Returns `nil` whenever AI is off, the feature is disabled, or the stored
/// endpoint is invalid, which is what hides the AI controls (graceful
/// degradation).
@MainActor
public final class AIEnvironment: AIModelCatalog {
    private let settingsRepository: any SettingRepository
    private let keychain: any KeychainStore
    private let requestLog = AIRequestLog()

    public init(
        settingsRepository: any SettingRepository,
        keychain: any KeychainStore
    ) {
        self.settingsRepository = settingsRepository
        self.keychain = keychain
    }

    /// The latest redacted request, for "What was sent".
    public var lastRequest: AIRequestInfo? { requestLog.last }

    /// Loads the saved endpoint settings and merges the Keychain key.
    public func loadSettings() async -> AIEndpointSettings {
        var settings = AIEndpointSettings()
        if let raw = await settingsRepository.value(for: SettingKeys.aiEndpoint),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AIEndpointSettings.self, from: data)
        {
            settings = decoded
        }
        if let key = await keychain.read(KeychainKeys.aiAPIKey), !key.isEmpty {
            settings.apiKey = key
        }
        return settings
    }

    /// An assistant for one feature, or `nil` when AI (or that feature) is
    /// disabled or misconfigured.
    public func assistant(for feature: String) async -> OpenAICompatibleAssistant? {
        let settings = await loadSettings()
        guard settings.enabled, settings.enabledFeatures.contains(feature) else {
            return nil
        }
        return makeAssistant(settings)
    }

    /// An assistant regardless of feature toggles, for Settings' model list.
    public func assistantForConfiguration() async -> OpenAICompatibleAssistant? {
        let settings = await loadSettings()
        guard settings.enabled else { return nil }
        return makeAssistant(settings)
    }

    private func makeAssistant(_ settings: AIEndpointSettings) -> OpenAICompatibleAssistant? {
        guard let configuration = try? AIConfiguration(settings: settings) else {
            return nil
        }
        let log = requestLog
        return OpenAICompatibleAssistant(
            configuration: configuration,
            onRequest: { log.record($0) }
        )
    }

    // MARK: - AIModelCatalog

    public func listModels() async throws -> [String] {
        guard let assistant = await assistantForConfiguration() else {
            throw AIError.disabled
        }
        return try await assistant.listModels()
    }

    /// Settings can fetch before Save: build the client from the in-memory form.
    public func listModels(for settings: AIEndpointSettings) async throws -> [String] {
        guard settings.enabled else { throw AIError.disabled }
        guard let assistant = makeAssistant(settings) else {
            throw AIError.invalidConfiguration("Check the base URL and model.")
        }
        return try await assistant.listModels()
    }
}
#endif
