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
    let vm: SettingsViewModel

    init() {
        let repository = InMemorySettingRepository()
        self.repository = repository
        vm = SettingsViewModel(repository: repository, calendar: testCalendar)
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

    // MARK: save

    @Test @MainActor
    func save_persistsBothGroups() async throws {
        let f = Fixture()
        f.vm.calendarSettings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])
        var ai = AIEndpointSettings()
        ai.enabled = true
        ai.model = "gpt-4o-mini"
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
        #expect(try decodeJSON(AIEndpointSettings.self, from: storedAI) == f.vm.aiSettings)
    }

    @Test @MainActor
    func save_failure_reportsLastError() async {
        let vm = SettingsViewModel(repository: FailingSettingRepository(), calendar: testCalendar)
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
        #expect(f.vm.aiSettings.baseURL == "http://localhost:11434/v1")

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
