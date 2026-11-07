import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private struct FakeInstaller: LocalModelInstaller {
    var running = true
    var installed: [String] = []
    var events: [LocalModelDownloadProgress] = []
    var failure: String?

    func isRunning() async -> Bool { running }

    func installedModelNames() async throws -> [String] { installed }

    func download(
        _ model: LocalAIModel
    ) -> AsyncThrowingStream<LocalModelDownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            if let failure {
                continuation.finish(throwing: FakeError(message: failure))
            } else {
                continuation.finish()
            }
        }
    }
}

private struct FakeError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct FakeDiscovery: LocalAIDiscovering {
    var candidates: [LocalAICandidate] = []
    func scan() async -> [LocalAICandidate] { candidates }
}

private actor PortRecordingDiscovery: LocalAIDiscovering {
    private(set) var ports: [Int?] = []

    func scan() async -> [LocalAICandidate] { [] }

    func scan(customPort: Int?) async -> [LocalAICandidate] {
        ports.append(customPort)
        return []
    }
}

@MainActor
private struct Fixture {
    let settings = InMemorySettingRepository()
    let keychain = InMemoryKeychainStore()
    let installer: FakeInstaller
    let model: AIOnboardingViewModel

    init(
        installer: FakeInstaller = FakeInstaller(),
        appleAvailable: Bool = true,
        discovering: any LocalAIDiscovering = NoLocalAIDiscovery()
    ) {
        self.installer = installer
        self.model = AIOnboardingViewModel(
            installer: installer,
            settings: settings,
            keychain: keychain,
            appleAvailable: appleAvailable,
            discovering: discovering
        )
    }

    func storedSettings() async -> AIEndpointSettings? {
        guard let raw = await settings.value(for: SettingKeys.aiEndpoint),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(AIEndpointSettings.self, from: data)
    }
}

@Suite("AI onboarding")
@MainActor
struct AIOnboardingViewModelTests {
    @Test func tinyModelShowsDownloadAndMemoryFootprint() {
        let model = LocalAIModel.tiny
        #expect(model.displayName == "Qwen3.5 0.8B")
        #expect(model.downloadSizeText == "533 MB")
        #expect(model.diskSizeText == "533 MB")
        #expect(model.memoryFootnote == "~1.5–2 GB while AI is running")
        #expect(model.license == "Apache 2.0")
    }

    @Test func skipMarksSetupCompleteAndLeavesAIOff() async {
        let fixture = Fixture()
        await fixture.model.skip()

        #expect(await fixture.settings.value(for: SettingKeys.aiSetupComplete) == "true")
        #expect(await fixture.storedSettings() == nil)
    }

    @Test func serverStateReportsWhetherTheModelIsInstalled() async {
        let installed = Fixture(
            installer: FakeInstaller(installed: [LocalAIModel.tiny.ollamaName])
        )
        await installed.model.refreshServer()
        #expect(installed.model.serverState == .ready(installedModel: true))

        let missing = Fixture()
        await missing.model.refreshServer()
        #expect(missing.model.serverState == .ready(installedModel: false))

        let offline = Fixture(installer: FakeInstaller(running: false))
        await offline.model.refreshServer()
        #expect(offline.model.serverState == .notRunning)
    }

    @Test func enableLocalWhenOllamaIsOffShowsAnErrorAndLeavesAIOff() async {
        let fixture = Fixture(installer: FakeInstaller(running: false))
        await fixture.model.refreshServer()
        await fixture.model.enableLocalModel()

        #expect(fixture.model.configuredOption == nil)
        #expect(fixture.model.lastError?.contains("Ollama") == true)
        #expect(await fixture.storedSettings() == nil)
    }

    @Test func enableLocalConfiguresOllamaAndAllFeatures() async {
        let fixture = Fixture(
            installer: FakeInstaller(installed: [LocalAIModel.tiny.ollamaName])
        )
        await fixture.model.refreshServer()
        await fixture.model.enableLocalModel()

        let saved = await fixture.storedSettings()
        #expect(saved?.enabled == true)
        #expect(saved?.provider == .ollama)
        #expect(saved?.baseURL == AIEndpointSettings.Provider.ollama.defaultBaseURL)
        #expect(saved?.model == LocalAIModel.tiny.ollamaName)
        #expect(saved?.enabledFeatures == AIFeatures.all)
        #expect(saved?.timeoutSeconds == 120)
        #expect(fixture.model.configuredOption == .local)
        #expect(await fixture.settings.value(for: SettingKeys.aiSetupComplete) == "true")
    }

    @Test func downloadAppliesProgressThenConfiguresOllama() async throws {
        let progress: [LocalModelDownloadProgress] = [
            LocalModelDownloadProgress(phase: .preparing, status: "pulling manifest"),
            LocalModelDownloadProgress(
                phase: .downloading,
                completedBytes: 250_000_000,
                totalBytes: 533_000_000,
                status: "downloading"
            ),
            LocalModelDownloadProgress(
                phase: .done,
                completedBytes: 533_000_000,
                totalBytes: 533_000_000,
                status: "success"
            ),
        ]
        let fixture = Fixture(installer: FakeInstaller(events: progress))
        await fixture.model.refreshServer()
        fixture.model.downloadLocalModel()
        try await waitUntil { fixture.model.configuredOption == .local }

        let saved = await fixture.storedSettings()
        #expect(saved?.enabled == true)
        #expect(saved?.provider == .ollama)
        #expect(saved?.model == LocalAIModel.tiny.ollamaName)
        #expect(fixture.model.downloadState == .completed)
    }

    @Test func downloadThatEndsWithoutSuccessDoesNotConfigure() async throws {
        let fixture = Fixture(
            installer: FakeInstaller(
                events: [
                    LocalModelDownloadProgress(
                        phase: .downloading,
                        completedBytes: 10,
                        totalBytes: 100,
                        status: "downloading"
                    )
                ]
            )
        )
        await fixture.model.refreshServer()
        fixture.model.downloadLocalModel()
        try await waitUntil {
            if case .failed = fixture.model.downloadState { return true }
            return false
        }

        #expect(fixture.model.configuredOption == nil)
        #expect(await fixture.storedSettings() == nil)
    }

    @Test func downloadFailureLeavesAIOffAndShowsTheError() async throws {
        let fixture = Fixture(installer: FakeInstaller(failure: "network down"))
        await fixture.model.refreshServer()
        fixture.model.downloadLocalModel()
        try await waitUntil {
            if case .failed = fixture.model.downloadState { return true }
            return false
        }

        #expect(fixture.model.configuredOption == nil)
        #expect(fixture.model.lastError == "network down")
        #expect(await fixture.storedSettings() == nil)
    }

    @Test func scanFindsLocalServersAndSelectsTheirFirstModel() async {
        let candidate = LocalAICandidate(
            id: "http://127.0.0.1:1234/v1",
            name: "LM Studio",
            baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
            provider: .lmStudio,
            models: ["qwen3-8b", "llama-3.2-3b"]
        )
        let fixture = Fixture(discovering: FakeDiscovery(candidates: [candidate]))

        await fixture.model.scanLocalAI()

        #expect(fixture.model.discovered == [candidate])
        #expect(fixture.model.selectedModels[candidate.id] == "qwen3-8b")
    }

    @Test func scanUsesTheCustomPort() async {
        let discovery = PortRecordingDiscovery()
        let fixture = Fixture(discovering: discovery)
        fixture.model.customScanPort = "8000"

        await fixture.model.scanLocalAI()

        #expect(await discovery.ports == [8000])
        #expect(fixture.model.lastError == nil)
    }

    @Test func scanRejectsAnInvalidCustomPort() async {
        let discovery = PortRecordingDiscovery()
        let fixture = Fixture(discovering: discovery)
        fixture.model.customScanPort = "not-a-port"

        await fixture.model.scanLocalAI()

        #expect(fixture.model.lastError != nil)
        #expect(await discovery.ports.isEmpty)
    }

    @Test func usingADetectedServerConfiguresTheProviderAndModel() async throws {
        let candidate = LocalAICandidate(
            id: "http://127.0.0.1:1234/v1",
            name: "LM Studio",
            baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
            provider: .lmStudio,
            models: ["qwen3-8b"]
        )
        let fixture = Fixture(discovering: FakeDiscovery(candidates: [candidate]))
        await fixture.model.scanLocalAI()
        await fixture.model.useDiscovered(candidate)

        let saved = try #require(await fixture.storedSettings())
        #expect(saved.enabled)
        #expect(saved.provider == .lmStudio)
        #expect(saved.baseURL == "http://127.0.0.1:1234/v1")
        #expect(saved.model == "qwen3-8b")
        #expect(saved.enabledFeatures == AIFeatures.all)
        #expect(fixture.model.configuredModelName == "LM Studio · qwen3-8b")
        #expect(await fixture.settings.value(for: SettingKeys.aiSetupComplete) == "true")
    }

    @Test func appleUnavailableDoesNotConfigureAnything() async {
        let fixture = Fixture(appleAvailable: false)
        await fixture.model.enableAppleIntelligence()

        #expect(fixture.model.configuredOption == nil)
        #expect(await fixture.storedSettings() == nil)
    }

    @Test func appleAvailableEnablesEmailSummaryOnly() async {
        let fixture = Fixture(appleAvailable: true)
        await fixture.model.enableAppleIntelligence()

        let saved = await fixture.storedSettings()
        #expect(saved?.enabled == true)
        #expect(saved?.provider == .apple)
        #expect(saved?.enabledFeatures == [AIFeatures.summarizeEmail])
        #expect(fixture.model.configuredOption == .apple)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                Issue.record("Timed out waiting for onboarding state")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
