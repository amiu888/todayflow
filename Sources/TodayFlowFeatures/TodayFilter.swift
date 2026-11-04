import Foundation

/// The Today list's filter chips (driver.md §4: [All] [Blocked] [P1–P2]).
public enum TodayFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case blocked
    case p1p2

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .blocked: return "Blocked"
        case .p1p2: return "P1–P2"
        }
    }
}

/// The Today list's sort order (driver.md §4: Sort▾ menu).
public enum TodaySort: String, CaseIterable, Identifiable, Sendable {
    case due
    case priority
    case manual

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .due: return "Due"
        case .priority: return "Priority"
        case .manual: return "Manual"
        }
    }
}
