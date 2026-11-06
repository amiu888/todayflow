import Foundation
import Testing
@testable import TodayFlowCore

struct InMemorySettingRepositoryTests {
    @Test func setAndGetRoundTrips() async throws {
        let repo = InMemorySettingRepository()
        try await repo.set("{\"startHour\":9}", for: "key")
        #expect(await repo.value(for: "key") == "{\"startHour\":9}")
    }

    @Test func absentKeyReturnsNil() async {
        let repo = InMemorySettingRepository()
        #expect(await repo.value(for: "missing") == nil)
    }

    @Test func setReplacesExistingValue() async throws {
        let repo = InMemorySettingRepository()
        try await repo.set("one", for: "key")
        try await repo.set("two", for: "key")
        #expect(await repo.value(for: "key") == "two")
    }

    @Test func removeDeletesValue() async throws {
        let repo = InMemorySettingRepository()
        try await repo.set("one", for: "key")
        try await repo.remove("key")
        #expect(await repo.value(for: "key") == nil)
    }

    @Test func removeAbsentKeyIsANoop() async throws {
        let repo = InMemorySettingRepository()
        try await repo.remove("missing") // must not throw
        #expect(await repo.value(for: "missing") == nil)
    }
}

struct WorkCalendarSettingsTests {
    @Test func defaultsMatchWorkCalendarStandard() {
        let settings = WorkCalendarSettings()
        #expect(settings.startHour == 9)
        #expect(settings.endHour == 17)
        #expect(settings.workWeekdays == [2, 3, 4, 5, 6])
    }

    @Test func codableRoundTrip() throws {
        let settings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(WorkCalendarSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func calendarMapsFieldByField() {
        let settings = WorkCalendarSettings(startHour: 8, endHour: 16, workWeekdays: [2, 3])
        let calendar = settings.calendar
        #expect(calendar.startHour == 8)
        #expect(calendar.endHour == 16)
        #expect(calendar.workWeekdays == Set([2, 3]))
    }

    @Test func initFromWorkCalendarSortsWeekdays() {
        let calendar = WorkCalendar(startHour: 9, endHour: 17, workWeekdays: [6, 2, 5, 3, 4])
        let settings = WorkCalendarSettings(calendar)
        #expect(settings.workWeekdays == [2, 3, 4, 5, 6])
    }
}

struct AIEndpointSettingsTests {
    @Test func defaultsAreOffWithAppleIntelligence() {
        let settings = AIEndpointSettings()
        #expect(settings.enabled == false)
        #expect(settings.provider == .apple)
        #expect(settings.baseURL == "")
        #expect(settings.apiKey.isEmpty)
        #expect(settings.model == AIEndpointSettings.tinyLocalModel)
        #expect(settings.enabledFeatures.isEmpty)
        #expect(settings.sendAttachmentText == false)
        #expect(settings.timeoutSeconds == 20)
    }

    @Test func providerPresetBaseURLs() {
        #expect(AIEndpointSettings.Provider.gpuBuddy.defaultBaseURL == "http://127.0.0.1:8080/v1")
        #expect(AIEndpointSettings.Provider.ollama.defaultBaseURL == "http://localhost:11434/v1")
        #expect(AIEndpointSettings.Provider.lmStudio.defaultBaseURL == "http://localhost:1234/v1")
        #expect(AIEndpointSettings.Provider.openai.defaultBaseURL == "https://api.openai.com/v1")
        #expect(AIEndpointSettings.Provider.custom.defaultBaseURL.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        var settings = AIEndpointSettings()
        settings.enabled = true
        settings.provider = .openai
        settings.baseURL = "https://api.openai.com/v1"
        settings.apiKey = "sk-test"
        settings.model = "gpt-4o-mini"
        settings.enabledFeatures = ["suggest", "plan_day"]
        settings.sendAttachmentText = true
        settings.timeoutSeconds = 45
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AIEndpointSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func featureKeysAreStable() {
        #expect(AIFeatures.all == ["suggest", "break_down", "plan_day", "ask", "summarize_email", "correct_text"])
        #expect(AIFeatures.label(for: AIFeatures.suggest) == "Suggest from capture")
        #expect(AIFeatures.label(for: AIFeatures.summarizeEmail) == "Summarize emails")
        #expect(AIFeatures.label(for: AIFeatures.correctText) == "Correct spelling & grammar")
        #expect(AIFeatures.label(for: "unknown") == "unknown")
    }
}
