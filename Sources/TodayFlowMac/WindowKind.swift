import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The app's window catalog (driver.md lines 145-152). Each kind maps to a
/// titled window with a default size and title taken from the design tokens.
public enum WindowKind: Hashable, Sendable {
    case panel
    case slimBar
    case hierarchy
    case calendar
    case insights
    case upcoming
    case completed
    case allTasks
    case history
    case settings
    case contacts
    case workflows
    case tutorial
    case detail(UUIDv7)

    public var title: String {
        switch self {
        case .panel: "Today"
        case .slimBar: "Today"
        case .hierarchy: "Hierarchy"
        case .calendar: "Calendar"
        case .insights: "Insights"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .allTasks: "All Tasks"
        case .history: "Task History"
        case .settings: "Settings"
        case .contacts: "Contacts"
        case .workflows: "Workflows"
        case .tutorial: "TodayFlow Tutorial"
        case .detail: "Task"
        }
    }

    public var size: CGSize {
        switch self {
        case .panel: DesignTokens.Window.panel
        case .slimBar: DesignTokens.Window.slimBar
        case .hierarchy: DesignTokens.Window.hierarchy
        case .calendar: DesignTokens.Window.calendar
        case .insights: CGSize(width: 540, height: 430)
        case .upcoming: DesignTokens.Window.upcoming
        case .completed: DesignTokens.Window.completed
        case .allTasks: CGSize(width: 760, height: 620)
        case .history: CGSize(width: 640, height: 620)
        case .settings: DesignTokens.Window.settings
        case .contacts: DesignTokens.Window.contacts
        case .workflows: CGSize(width: 920, height: 620)
        case .tutorial: CGSize(width: 960, height: 620)
        case .detail: DesignTokens.Window.detail
        }
    }
}
