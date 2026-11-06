import Foundation

/// A suggested task produced by the LLM from a drop (driver.md §8).
///
/// Every field is a *suggestion*: the capture sheet shows it for approval and
/// nothing is created until the user saves.
public struct TaskSuggestion: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String
    public var priority: Priority
    public var actions: [String]

    public init(
        title: String,
        summary: String = "",
        priority: Priority = .default,
        actions: [String] = []
    ) {
        self.title = title
        self.summary = summary
        self.priority = priority
        self.actions = actions
    }
}

/// One suggested subtask from "Break down a task" (driver.md §8).
public struct SubtaskSuggestion: Codable, Hashable, Sendable, Identifiable {
    public var title: String
    public var details: String
    public var estimatedMinutes: Int?

    /// Titles are unique within one suggestion; the UI keeps the model's order.
    public var id: String { title }

    public init(title: String, details: String = "", estimatedMinutes: Int? = nil) {
        self.title = title
        self.details = details
        self.estimatedMinutes = estimatedMinutes
    }
}

/// A proposed order for the day (driver.md §8 "Plan my day").
///
/// Entries reference existing work items by id; the feature layer decides
/// whether to apply the order. Unknown ids are discarded, so a hallucinated
/// item can never be reordered or created.
public struct DayPlan: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var itemId: UUIDv7
        public var reason: String

        public var id: UUIDv7 { itemId }

        public init(itemId: UUIDv7, reason: String = "") {
            self.itemId = itemId
            self.reason = reason
        }
    }

    public var summary: String
    public var order: [Entry]

    public init(summary: String = "", order: [Entry] = []) {
        self.summary = summary
        self.order = order
    }
}

/// Port for the optional AI features (driver.md §8).
///
/// Implementations live in TodayFlowAI and talk to any OpenAI-compatible
/// endpoint. The protocol is in Core so the UI depends only on the port; AI is
/// off by default and every method may throw when the endpoint is unreachable.
public protocol AIAssistant: Sendable {
    /// Smart title, summary, priority, and suggested actions for a drop.
    func suggestTask(from objects: [RecognizedObject]) async throws -> TaskSuggestion

    /// Actions/subtasks for an existing task.
    func breakDown(_ item: WorkItem) async throws -> [SubtaskSuggestion]

    /// A proposed order for the day, with a reason per item.
    func planDay(_ items: [WorkItem], hours: WorkCalendar) async throws -> DayPlan

    /// Free-form questions answered from the supplied local context, streamed.
    func ask(
        _ question: String,
        context: [WorkItem]
    ) async throws -> AsyncThrowingStream<String, Error>

    /// Corrects spelling, grammar, punctuation, and sentence boundaries while
    /// preserving meaning, names, URLs, and formatting.
    func correctText(_ text: String) async throws -> String
}

public enum AIAssistantError: Error, LocalizedError, Sendable {
    case textCorrectionUnavailable

    public var errorDescription: String? {
        "Text correction is not available."
    }
}

public extension AIAssistant {
    /// Optional capability: older assistants and test doubles can opt out.
    func correctText(_ text: String) async throws -> String {
        throw AIAssistantError.textCorrectionUnavailable
    }
}

/// Optional model discovery for the Settings "Fetch models" control
/// (driver.md §8 configuration table).
public protocol AIModelCatalog: Sendable {
    func listModels() async throws -> [String]

    /// Lists models for the settings currently being edited, before Save.
    /// The default implementation ignores the override.
    func listModels(for settings: AIEndpointSettings) async throws -> [String]
}

public extension AIModelCatalog {
    func listModels(for settings: AIEndpointSettings) async throws -> [String] {
        try await listModels()
    }
}
