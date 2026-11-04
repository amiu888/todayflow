import Foundation
import Observation
import TodayFlowCore

/// Model for the settings screen (driver.md §11 feature 5).
///
/// Owns the two settings groups the app persists in the `setting` store:
/// business hours (`WorkCalendarSettings`, driver.md line 49) and the AI
/// endpoint (`AIEndpointSettings`, driver.md §8). The view edits the observed
/// copies; `save()` persists both.
@MainActor
@Observable
public final class SettingsViewModel {
    // MARK: Observed state

    /// Business hours. Editing these changes the `workCalendar` below, which
    /// is what computes default end dates.
    public var calendarSettings = WorkCalendarSettings()

    /// AI endpoint (off by default).
    public var aiSettings = AIEndpointSettings() {
        didSet {
            // When the user picks a different provider, fill in the preset's
            // base URL — but only if the current URL is still a preset default
            // (or empty); a user-customized URL is preserved.
            guard !isApplying, aiSettings.provider != oldValue.provider else { return }
            if oldValue.baseURL == oldValue.provider.defaultBaseURL || oldValue.baseURL.isEmpty {
                aiSettings.baseURL = aiSettings.provider.defaultBaseURL
            }
        }
    }

    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var lastError: String?

    // MARK: Dependencies

    @ObservationIgnored private let repository: any SettingRepository
    @ObservationIgnored private let calendar: Calendar

    /// True while `load()`/`resetToDefaults()` are applying stored values —
    /// suppresses the provider didSet side effect for programmatic writes.
    @ObservationIgnored private var isApplying = false

    public init(
        repository: any SettingRepository,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.calendar = calendar
    }

    /// The `WorkCalendar` derived from the current business-hours settings —
    /// what hosts (the Today list, capture) use to compute default end dates.
    public var workCalendar: WorkCalendar {
        WorkCalendar(
            startHour: calendarSettings.startHour,
            endHour: calendarSettings.endHour,
            workWeekdays: Set(calendarSettings.workWeekdays),
            calendar: calendar
        )
    }

    // MARK: Actions

    /// Loads both groups from the store; an absent or corrupt stored value
    /// falls back to the group's defaults (a bad value must never break the UI).
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        isApplying = true
        defer { isApplying = false }

        calendarSettings = Self.calendarSettings(from: await repository.value(for: SettingKeys.workCalendar))
        aiSettings = Self.aiSettings(from: await repository.value(for: SettingKeys.aiEndpoint))
    }

    /// Persists both groups.
    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        lastError = nil
        do {
            try await repository.set(
                try Self.encode(calendarSettings),
                for: SettingKeys.workCalendar
            )
            try await repository.set(
                try Self.encode(aiSettings),
                for: SettingKeys.aiEndpoint
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Restores both groups to their defaults and persists them.
    public func resetToDefaults() async {
        isApplying = true
        calendarSettings = WorkCalendarSettings()
        aiSettings = AIEndpointSettings()
        isApplying = false
        await save()
    }

    // MARK: Encoding

    private static func calendarSettings(from value: String?) -> WorkCalendarSettings {
        guard let value,
              let decoded = try? JSONDecoder().decode(WorkCalendarSettings.self, from: Data(value.utf8))
        else {
            return WorkCalendarSettings()
        }
        return decoded
    }

    private static func aiSettings(from value: String?) -> AIEndpointSettings {
        guard let value,
              let decoded = try? JSONDecoder().decode(AIEndpointSettings.self, from: Data(value.utf8))
        else {
            return AIEndpointSettings()
        }
        return decoded
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
