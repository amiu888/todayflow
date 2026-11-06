import Foundation

/// Keys under which the app persists its settings in the `setting` store
/// (driver.md §6).
public enum SettingKeys {
    public static let workCalendar = "work_calendar"
    public static let aiEndpoint = "ai_endpoint"
    /// Set after the first-run AI choice (including "skip"), so the optional
    /// setup window is not shown again on every launch.
    public static let aiSetupComplete = "ai_setup_complete"
    /// The Today list's sort choice (driver.md FR-11: "Choice is persisted").
    /// Stored as the `TodaySort` raw value (a plain string, not JSON).
    public static let todaySort = "today_sort"
    /// The working-tray strip, encoded as `[WorkTray]` JSON.
    public static let workTrays = "work_trays"
    /// The tray automation rules, encoded as `[TrayWorkflowRule]` JSON.
    public static let workflowRules = "workflow_rules"
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
    /// The optional first-run/local default. Pulled through Ollama from the
    /// Unsloth GGUF (Q4_K_M, Apache 2.0) so the download stays around 533 MB
    /// instead of the official Ollama Q8 + vision bundle.
    public static let tinyLocalModel = "hf.co/unsloth/Qwen3.5-0.8B-GGUF:Q4_K_M"
    public static let tinyLocalModelDisplayName = "Qwen3.5 0.8B"
    public static let tinyLocalModelDownloadBytes: Int64 = 533_000_000
    public static let tinyLocalModelDiskBytes: Int64 = 533_000_000
    public static let tinyLocalModelMemoryFootnote = "~1.5–2 GB while AI is running"

    /// A provider preset; picking one fills in its base URL.
    public enum Provider: String, Codable, CaseIterable, Hashable, Sendable {
        case apple
        case ollama
        case lmStudio = "lm-studio"
        case openai
        case custom

        public var label: String {
            switch self {
            case .apple: return "Apple Intelligence"
            case .ollama: return "Ollama"
            case .lmStudio: return "LM Studio"
            case .openai: return "OpenAI"
            case .custom: return "Custom"
            }
        }

        /// The preset's default base URL (driver.md §8: "Preset fills base URL").
        public var defaultBaseURL: String {
            switch self {
            case .apple: return ""
            case .ollama: return "http://localhost:11434/v1"
            case .lmStudio: return "http://localhost:1234/v1"
            case .openai: return "https://api.openai.com/v1"
            case .custom: return ""
            }
        }
    }

    /// Master toggle — AI is off by default.
    public var enabled: Bool = false
    /// Apple Intelligence is the preferred on-device provider for new installs.
    public var provider: Provider = .apple
    /// Any OpenAI-compatible endpoint (`POST {baseURL}/chat/completions`).
    public var baseURL: String = ""
    /// Optional for local servers.
    ///
    /// The one AI setting that does not live in the settings store: the 6-Mac
    /// app layer keeps it in the `KeychainStore` (driver.md line 411 /
    /// NFR-10: API keys in Keychain). The stored JSON copy is redacted (`""`)
    /// on save; a non-empty value still in a pre-6.3 store is migrated to the
    /// Keychain on load.
    public var apiKey: String = ""
    /// Free text; the "Fetch models" button (feature 7) lists the endpoint's models.
    ///
    /// The small local default is a 4-bit Qwen3.5 0.8B (~533 MB) so a new
    /// Ollama install never silently pulls a multi-gigabyte model.
    public var model: String = AIEndpointSettings.tinyLocalModel
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
    /// Summarize an email into the task summary.
    public static let summarizeEmail = "summarize_email"

    public static let all: [String] = [suggest, breakDown, planDay, ask, summarizeEmail]

    public static func label(for key: String) -> String {
        switch key {
        case suggest: return "Suggest from capture"
        case breakDown: return "Break tasks down"
        case planDay: return "Plan my day"
        case ask: return "Ask questions"
        case summarizeEmail: return "Summarize emails"
        default: return key
        }
    }
}
