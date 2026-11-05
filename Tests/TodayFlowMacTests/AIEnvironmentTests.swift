#if canImport(AppKit)
import Foundation
import Testing
import TodayFlowAI
import TodayFlowCore
import TodayFlowMac

@Suite("AIEnvironment")
@MainActor
struct AIEnvironmentTests {
    private func store(_ settings: AIEndpointSettings) async throws -> InMemorySettingRepository {
        let repository = InMemorySettingRepository()
        let data = try JSONEncoder().encode(settings)
        try await repository.set(String(decoding: data, as: UTF8.self), for: SettingKeys.aiEndpoint)
        return repository
    }

    @Test func everyAIFeatureIsUnavailableWhenAIIsOff() async {
        let repository = InMemorySettingRepository()
        let ai = AIEnvironment(
            settingsRepository: repository,
            keychain: InMemoryKeychainStore()
        )

        for feature in AIFeatures.all {
            #expect(await ai.assistant(for: feature) == nil)
        }
        #expect(await ai.assistantForConfiguration() == nil)
        #expect(await ai.emailSummarizer() == nil)
    }

    @Test func emailSummarizerIsNilWhenTheFeatureIsOff() async {
        var settings = AIEndpointSettings()
        settings.enabled = true
        settings.provider = .openai
        settings.baseURL = "https://api.openai.com/v1"
        settings.model = "gpt-4.1-mini"
        settings.enabledFeatures = [AIFeatures.suggest]
        let repository = try! await store(settings)
        let ai = AIEnvironment(
            settingsRepository: repository,
            keychain: InMemoryKeychainStore()
        )

        #expect(await ai.emailSummarizer() == nil)
    }

    @Test func emailSummarizerUsesTheConfiguredOpenAIEndpoint() async {
        var settings = AIEndpointSettings()
        settings.enabled = true
        settings.provider = .openai
        settings.baseURL = "https://api.openai.com/v1"
        settings.model = "gpt-4.1-mini"
        settings.enabledFeatures = [AIFeatures.summarizeEmail]
        let repository = try! await store(settings)
        let ai = AIEnvironment(
            settingsRepository: repository,
            keychain: InMemoryKeychainStore()
        )

        #expect(await ai.emailSummarizer() != nil)
    }
}
#endif
