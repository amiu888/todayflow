import Foundation

/// The simple trigger vocabulary for tray workflows. Every rule is a
/// "when [trigger] in [source tray], move the task to [target tray]" sentence.
public enum TrayWorkflowTrigger: String, Codable, CaseIterable, Sendable, Identifiable {
    /// The task's status becomes done while it is in the source tray.
    case completed
    /// The task's due date/time is reached while it is in the source tray.
    case dueReached

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .completed: return "Task is completed"
        case .dueReached: return "Due date is reached"
        }
    }

    public var shortLabel: String {
        switch self {
        case .completed: return "completed"
        case .dueReached: return "due"
        }
    }

    public var detail: String {
        switch self {
        case .completed: return "Moves finished tasks to the target tray."
        case .dueReached: return "Moves open tasks when their due date passes."
        }
    }
}

/// One trigger → one action. Kept intentionally small: no branches, loops, or
/// parallel paths, so a workflow can be read as one sentence.
public struct TrayWorkflowRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUIDv7
    public var sourceTrayId: UUIDv7
    public var targetTrayId: UUIDv7
    public var trigger: TrayWorkflowTrigger
    public var isEnabled: Bool

    public init(
        id: UUIDv7 = .new(),
        sourceTrayId: UUIDv7,
        targetTrayId: UUIDv7,
        trigger: TrayWorkflowTrigger,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.sourceTrayId = sourceTrayId
        self.targetTrayId = targetTrayId
        self.trigger = trigger
        self.isEnabled = isEnabled
    }

    public var isValid: Bool {
        sourceTrayId != targetTrayId
    }
}
