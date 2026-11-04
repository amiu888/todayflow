import Foundation

/// Keys under which the app persists its settings in the `setting` store
/// (driver.md §6).
public enum SettingKeys {
    public static let workCalendar = "work_calendar"
    public static let aiEndpoint = "ai_endpoint"
}

/// The user's business hours (driver.md line 49: the WorkCalendar settings
/// used to compute default end dates).
///
/// Weekdays are a sorted array (not a `Set`) so the JSON encoding is stable.
public struct WorkCalendarSettings: Codable, Hashable, Sendable {
    /// Hour of day, 0–23 (9 = 09:00).
    public var startHour: Double
    /// Hour of day, 0–23 (17 = 17:00, end of business).
    public var endHour: Double
    /// `Calendar` weekday numbers: 1 = Sunday … 7 = Saturday.
    /// `[2, 3, 4, 5, 6]` = Monday–Friday.
    public var workWeekdays: [Int]

    public init(
        startHour: Double = 9,
        endHour: Double = 17,
        workWeekdays: [Int] = [2, 3, 4, 5, 6]
    ) {
        self.startHour = startHour
        self.endHour = endHour
        self.workWeekdays = workWeekdays
    }

    /// The `WorkCalendar` these settings describe (using the system calendar).
    public var calendar: WorkCalendar {
        WorkCalendar(
            startHour: startHour,
            endHour: endHour,
            workWeekdays: Set(workWeekdays),
            calendar: .current
        )
    }

    public init(_ calendar: WorkCalendar) {
        self.startHour = calendar.startHour
        self.endHour = calendar.endHour
        self.workWeekdays = calendar.workWeekdays.sorted()
    }
}

/// The AI endpoint settings (driver.md §8, the Settings → AI table).
///
/// AI is optional and **off by default** (`enabled == false`).
public struct AIEndpointSettings: Codable, Hashable, Sendable {
    /// A provider preset; picking one fills in its base URL.
    public enum Provider: String, Codable, CaseIterable, Hashable, Sendable {
        case ollama
        case lmStudio = "lm-studio"
        case openai
        case custom

        public var label: String {
            switch self {
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            case .openai: return "OpenAI"
            case .custom: return "Custom"
            }
        }

        /// The preset's default base URL (driver.md §8: "Preset fills base URL").
        public var defaultBaseURL: String {
            switch self {
            case .ollama: return "http://localhost:11434/v1"
            case .lmStudio: return "http://localhost:1234/v1"
            case .openai: return "https://api.openai.com/v1"
            case .custom: return ""
            }
        }
    }

    /// Master toggle — AI is off by default.
    public var enabled: Bool = false
    public var provider: Provider = .ollama
    /// Any OpenAI-compatible endpoint (`POST {baseURL}/chat/completions`).
    public var baseURL: String = Provider.ollama.defaultBaseURL
    /// Optional for local servers.
    ///
    /// 5e stores it in the settings store like every other value; the 6-Mac
    /// app layer moves it to the Keychain per driver.md §8.
    public var apiKey: String = ""
    /// Free text; the "Fetch models" button (feature 7) lists the endpoint's models.
    public var model: String = "llama3.1:8b"
    /// Which AI features are on (`AIFeatures` keys).
    public var enabledFeatures: [String] = []
    /// Privacy: off sends only titles and metadata.
    public var sendAttachmentText: Bool = false
    /// AI must never block capture; this is the request timeout.
    public var timeoutSeconds: Double = 20

    public init() {}
}

/// The AI features with per-feature toggles (driver.md §8:
/// "Features — toggles per feature").
public enum AIFeatures {
    /// Suggest a task from a dropped object (capture).
    public static let suggest = "suggest"
    /// Break a task down into subtasks.
    public static let breakDown = "break_down"
    /// Plan the day from the today list.
    public static let planDay = "plan_day"
    /// Free-form questions with item context.
    public static let ask = "ask"

    public static let all: [String] = [suggest, breakDown, planDay, ask]

    public static func label(for key: String) -> String {
        switch key {
        case suggest: return "Suggest from capture"
        case breakDown: return "Break tasks down"
        case planDay: return "Plan my day"
        case ask: return "Ask questions"
        default: return key
        }
    }
}
