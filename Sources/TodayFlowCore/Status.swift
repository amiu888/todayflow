import Foundation

/// Lifecycle status of a work item (driver.md §2).
///
/// `blocked` is a *derived* presentation state: an item that is not done/cancelled
/// but has an unresolved blocking link is surfaced as blocked. The stored status is
/// recomputed by the use cases; it is not something the user sets directly.
public enum Status: String, Codable, CaseIterable, Sendable, Hashable {
    case todo
    case inProgress
    case blocked
    case done
    case cancelled

    public var label: String {
        switch self {
        case .todo:       return "To do"
        case .inProgress: return "In progress"
        case .blocked:    return "Blocked"
        case .done:       return "Done"
        case .cancelled:  return "Cancelled"
        }
    }

    /// SF Symbol name for the status (driver.md §4).
    public var symbolName: String {
        switch self {
        case .todo:       return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .blocked:    return "exclamationmark.circle"
        case .done:       return "checkmark.circle.fill"
        case .cancelled:  return "xmark.circle"
        }
    }

    /// Counts toward "complete" for progress roll-up.
    public var isComplete: Bool { self == .done }

    /// Terminal states: no further status transitions are expected.
    public var isTerminal: Bool { self == .done || self == .cancelled }
}
