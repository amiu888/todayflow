import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@MainActor
private struct Fixture {
    let repository: InMemorySettingRepository
    let keychain: InMemoryKeychainStore
    let vm: SettingsViewModel

    init() {
        let repository = InMemorySettingRepository()
        let keychain = InMemoryKeychainStore()
        self.repository = repository
        self.keychain = keychain
        vm = SettingsViewModel(repository: repository, keychain: keychain, calendar: testCalendar)
    }
}

/// A `SettingRepository` whose writes fail — for error-path tests.
private struct FailingSettingRepository: SettingRepository {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "the settings store is unavailable" }
    }

    func value(for key: String) async -> String? { nil }
    func set(_ valueJson: String, for key: String) async throws { throw Failure() }
    func remove(_ key: String) async throws {}
}

/// A `KeychainStore` whose mutations fail — for error-path tests.
private struct FailingKeychainStore: KeychainStore {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "the keychain is unavailable" }
    }

    func read(_ key: String) async -> String? { nil }
    func write(_ value: String, for key: String) async throws { throw Failure() }
    func delete(_ key: String) async throws { throw Failure() }
}

/// Encodes a settings value the same way the view model does.
private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

private func decodeJSON<T: Decodable>(_ type: T.Type, from value: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(value.utf8))
}

struct SettingsViewModelTests {
    // MARK: load

    @Test @MainActor
    func load_emptyStore_yieldsDefaults() async {
        let f = Fixture()
        await f.vm.load()

        #expect(f.vm.calendarSettings == WorkCalendarSettings())
        #expect(f.vm.aiSettings == AIEndpointSettings())
        #expect(f.vm.lastError == nil)
    }

    @Test @MainActor
    func load_readsStoredObsidianSettings() async throws {
        let f = Fixture()
        let stored = ObsidianSettings(
            enabled: true,
            vaultPath: "/Users/me/Vault",
            vaultName: "Vault",
            notePath: "TodayFlow/Tasks.md"
        )
        try await f.repository.set(try encodeJSON(stored), for: SettingKeys.obsidian)
        await f.vm.load()

        #expect(f.vm.obsidianSettings == stored)
    }

    @Test @MainActor
    func load_readsStoredValues() async throws {
        let f = Fixture()
        let storedCalendar = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3, 4])
        var storedAI = AIEndpointSettings()
        storedAI.enabled = true
        storedAI.provider = .lmStudio
        storedAI.baseURL = "http://192.168.1.50:1234/v1"
        storedAI.model = "qwen3:8b"
        storedAI.enabledFeatures = ["suggest"]
        storedAI.timeoutSeconds = 30

        try await f.repository.set(try encodeJSON(storedCalendar), for: SettingKeys.workCalendar)
        try await f.repository.set(try encodeJSON(storedAI), for: SettingKeys.aiEndpoint)
        await f.vm.load()

        #expect(f.vm.calendarSettings == storedCalendar)
        #expect(f.vm.aiSettings == storedAI)
    }

    @Test @MainActor
    func load_corruptValue_fallsBackToDefaults() async throws {
        let f = Fixture()
        try await f.repository.set("{not json", for: SettingKeys.workCalendar)
        try await f.repository.set("42", for: SettingKeys.aiEndpoint)
        await f.vm.load()

        #expect(f.vm.calendarSettings == WorkCalendarSettings())
        #expect(f.vm.aiSettings == AIEndpointSettings())
    }

    @Test @MainActor
    func load_readsObsidianAPIKeyFromKeychain() async throws {
        let f = Fixture()
        try await f.keychain.write("remote-key", for: KeychainKeys.obsidianAPIKey)
        await f.vm.load()
        #expect(f.vm.obsidianAPIKey == "remote-key")
    }

    @Test @MainActor
    func save_persistsObsidianAPIKeyToKeychain() async throws {
        let f = Fixture()
        await f.vm.load()
        f.vm.obsidianAPIKey = "remote-key"

        await f.vm.save()

        #expect(await f.keychain.read(KeychainKeys.obsidianAPIKey) == "remote-key")
        let raw = try #require(await f.repository.value(for: SettingKeys.obsidian))
        #expect(!raw.contains("remote-key"))
    }

    @Test @MainActor
    func save_persistsObsidianSettings() async throws {
        let f = Fixture()
        await f.vm.load()
        f.vm.obsidianSettings = ObsidianSettings(
            enabled: true,
            vaultPath: "/Users/me/Vault",
            vaultName: "Vault",
            notePath: "Notes/TodayFlow.md"
        )

        await f.vm.save()

        let raw = try #require(await f.repository.value(for: SettingKeys.obsidian))
        let stored = try decodeJSON(ObsidianSettings.self, from: raw)
        #expect(stored == f.vm.obsidianSettings)
    }

    // MARK: save

    @Test @MainActor
    func save_persistsBothGroups() async throws {
        let f = Fixture()
        f.vm.calendarSettings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])
        var ai = AIEndpointSettings()
        ai.enabled = true
        ai.model = "gpt-4o-mini"
        ai.apiKey = "sk-test-123"
        f.vm.aiSettings = ai

        await f.vm.save()

        #expect(f.vm.lastError == nil)
        let storedCalendar = await f.repository.value(for: SettingKeys.workCalendar)
        let storedAI = await f.repository.value(for: SettingKeys.aiEndpoint)
        guard let storedCalendar, let storedAI else {
            Issue.record("both groups must be persisted")
            return
        }

        #expect(try decodeJSON(WorkCalendarSettings.self, from: storedCalendar) == f.vm.calendarSettings)
        // The stored copy is redacted; the key lives in the Keychain.
        var redacted = f.vm.aiSettings
        redacted.apiKey = ""
        #expect(try decodeJSON(AIEndpointSettings.self, from: storedAI) == redacted)
        let keychainKey = await f.keychain.read(KeychainKeys.aiAPIKey)
        #expect(keychainKey == "sk-test-123")
    }

    @Test @MainActor
    func save_failure_reportsLastError() async {
        let vm = SettingsViewModel(
            repository: FailingSettingRepository(),
            keychain: InMemoryKeychainStore(),
            calendar: testCalendar
        )
        await vm.save()

        #expect(vm.lastError != nil)
    }

    @Test @MainActor
    func save_twice_persistsLatest() async throws {
        let f = Fixture()
        f.vm.calendarSettings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])
        await f.vm.save()

        f.vm.calendarSettings = WorkCalendarSettings(startHour: 10, endHour: 18, workWeekdays: [2, 3, 4, 5, 6, 7])
        await f.vm.save()

        let raw = await f.repository.value(for: SettingKeys.workCalendar)
        let decoded = try decodeJSON(WorkCalendarSettings.self, from: raw!)
        #expect(decoded.startHour == 10)
        #expect(decoded.endHour == 18)
        #expect(decoded.workWeekdays == [2, 3, 4, 5, 6, 7])
    }

    @Test @MainActor
    func edits_markUnsaved_andSaveClears() async {
        let f = Fixture()
        await f.vm.load()
        #expect(!f.vm.hasUnsavedChanges)
        #expect(!f.vm.didSave)

        f.vm.obsidianSettings.notePath = "Other/Tasks.md"
        #expect(f.vm.hasUnsavedChanges)
        #expect(!f.vm.didSave)

        await f.vm.save()
        #expect(!f.vm.hasUnsavedChanges)
        #expect(f.vm.didSave)

        f.vm.obsidianAPIKey = "remote-key"
        #expect(f.vm.hasUnsavedChanges)
        #expect(!f.vm.didSave)
    }

    @Test @MainActor
    func failedSave_keepsUnsavedChanges() async {
        let vm = SettingsViewModel(
            repository: FailingSettingRepository(),
            keychain: InMemoryKeychainStore(),
            calendar: testCalendar
        )
        vm.calendarSettings = WorkCalendarSettings(startHour: 7, endHour: 15)
        #expect(vm.hasUnsavedChanges)

        await vm.save()
        #expect(vm.lastError != nil)
        #expect(vm.hasUnsavedChanges)
        #expect(!vm.didSave)
    }

    // MARK: reset

    @Test @MainActor
    func resetToDefaults_restoresAndPersists() async throws {
        let f = Fixture()
        f.vm.calendarSettings = WorkCalendarSettings(startHour: 6, endHour: 12, workWeekdays: [1])
        var ai = AIEndpointSettings()
        ai.enabled = true
        ai.model = "custom-model"
        f.vm.aiSettings = ai
        await f.vm.save()

        await f.vm.resetToDefaults()

        #expect(f.vm.calendarSettings == WorkCalendarSettings())
        #expect(f.vm.aiSettings == AIEndpointSettings())
        let storedCalendar = await f.repository.value(for: SettingKeys.workCalendar)
        let storedAI = await f.repository.value(for: SettingKeys.aiEndpoint)
        #expect(try decodeJSON(WorkCalendarSettings.self, from: storedCalendar!) == WorkCalendarSettings())
        #expect(try decodeJSON(AIEndpointSettings.self, from: storedAI!) == AIEndpointSettings())
    }

    // MARK: provider change

    @Test @MainActor
    func providerChange_fillsPresetBaseURL() {
        let f = Fixture()
        #expect(f.vm.aiSettings.baseURL == "")

        f.vm.aiSettings.provider = .openai

        #expect(f.vm.aiSettings.baseURL == "https://api.openai.com/v1")
    }

    @Test @MainActor
    func providerChange_keepsCustomBaseURL() {
        let f = Fixture()
        f.vm.aiSettings.baseURL = "http://my-gpu-box:11434/v1"

        f.vm.aiSettings.provider = .lmStudio

        #expect(f.vm.aiSettings.baseURL == "http://my-gpu-box:11434/v1")
    }

    @Test @MainActor
    func load_doesNotRewriteCustomBaseURL() async throws {
        let f = Fixture()
        var stored = AIEndpointSettings()
        stored.enabled = true
        stored.provider = .openai
        stored.baseURL = "http://proxy.internal/v1"
        try await f.repository.set(try encodeJSON(stored), for: SettingKeys.aiEndpoint)

        await f.vm.load()

        #expect(f.vm.aiSettings.baseURL == "http://proxy.internal/v1")
    }

    // MARK: API key in the Keychain (driver.md line 411, NFR-10)

    @Test @MainActor
    func load_readsKeyFromKeychain() async throws {
        let f = Fixture()
        // A pre-6.3 store with a key, and a Keychain holding a different (newer) key.
        var stored = AIEndpointSettings()
        stored.apiKey = "sk-stale"
        try await f.repository.set(try encodeJSON(stored), for: SettingKeys.aiEndpoint)
        await f.keychain.seed("sk-current", for: KeychainKeys.aiAPIKey)

        await f.vm.load()

        #expect(f.vm.aiSettings.apiKey == "sk-current")
    }

    @Test @MainActor
    func load_migratesStoredKeyToKeychain() async throws {
        let f = Fixture()
        var stored = AIEndpointSettings()
        stored.apiKey = "sk-stored"
        try await f.repository.set(try encodeJSON(stored), for: SettingKeys.aiEndpoint)

        await f.vm.load()

        #expect(f.vm.aiSettings.apiKey == "sk-stored")
        #expect(await f.keychain.read(KeychainKeys.aiAPIKey) == "sk-stored")
    }

    @Test @MainActor
    func save_emptyKey_deletesKeychainEntry() async throws {
        let f = Fixture()
        await f.keychain.seed("sk-obsolete", for: KeychainKeys.aiAPIKey)

        await f.vm.save()

        #expect(f.vm.lastError == nil)
        #expect(await f.keychain.read(KeychainKeys.aiAPIKey) == nil)
    }

    @Test @MainActor
    func resetToDefaults_wipesKeychain() async throws {
        let f = Fixture()
        var ai = AIEndpointSettings()
        ai.enabled = true
        ai.apiKey = "sk-live"
        f.vm.aiSettings = ai
        f.vm.obsidianAPIKey = "remote-key"
        await f.vm.save()
        #expect(await f.keychain.read(KeychainKeys.aiAPIKey) == "sk-live")
        #expect(await f.keychain.read(KeychainKeys.obsidianAPIKey) == "remote-key")

        await f.vm.resetToDefaults()

        #expect(f.vm.aiSettings == AIEndpointSettings())
        #expect(f.vm.obsidianAPIKey.isEmpty)
        #expect(f.vm.obsidianSettings == ObsidianSettings())
        #expect(await f.keychain.read(KeychainKeys.aiAPIKey) == nil)
        #expect(await f.keychain.read(KeychainKeys.obsidianAPIKey) == nil)
    }

    @Test @MainActor
    func save_keychainFailure_reportsLastErrorAndKeepsStoreUntouched() async throws {
        let repository = InMemorySettingRepository()
        let vm = SettingsViewModel(
            repository: repository,
            keychain: FailingKeychainStore(),
            calendar: testCalendar
        )
        var ai = AIEndpointSettings()
        ai.apiKey = "sk-test"
        vm.aiSettings = ai

        await vm.save()

        #expect(vm.lastError != nil)
        #expect(await repository.value(for: SettingKeys.aiEndpoint) == nil)
    }

    // MARK: workCalendar

    @Test @MainActor
    func workCalendar_derivesFromCurrentSettings() {
        let f = Fixture()
        f.vm.calendarSettings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])

        let calendar = f.vm.workCalendar
        #expect(calendar.startHour == 8)
        #expect(calendar.endHour == 16)
        #expect(calendar.workWeekdays == Set([2, 3]))
        #expect(calendar.calendar == testCalendar)
    }
}
