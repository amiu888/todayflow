import Foundation

/// Task priority (driver.md §2). Ordered so that lower raw values are more urgent.
public enum Priority: Int, Codable, CaseIterable, Sendable, Comparable, Hashable {
    case urgent = 1
    case high = 2
    case normal = 3
    case low = 4

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Default priority for a newly captured task (driver.md §2: P3 Normal).
    public static let `default` = Priority.normal

    /// Human-readable label, e.g. "P1 Urgent".
    public var label: String {
        switch self {
        case .urgent: return "P1 Urgent"
        case .high:   return "P2 High"
        case .normal: return "P3 Normal"
        case .low:    return "P4 Low"
        }
    }

    /// SF Symbol point name for the priority dot (driver.md §4).
    public var symbolName: String {
        "circle.fill"
    }
}
