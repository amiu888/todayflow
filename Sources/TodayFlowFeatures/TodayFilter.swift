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
///
/// Case order is the menu order (FR-11: "Display order (default), Priority then
/// due date, Due date then priority"). The raw values are stable — they are what
/// gets persisted via `SettingKeys.todaySort`.
public enum TodaySort: String, CaseIterable, Identifiable, Sendable {
    case manual
    case priority
    case due

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .manual: return "Display order"
        case .priority: return "Priority then due date"
        case .due: return "Due date then priority"
        }
    }
}
