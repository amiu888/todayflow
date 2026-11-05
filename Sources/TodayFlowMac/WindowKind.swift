import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The app's window catalog (driver.md lines 145-152). Each kind maps to a
/// titled window with a default size and title taken from the design tokens.
public enum WindowKind: Hashable, Sendable {
    case panel
    case slimBar
    case hierarchy
    case upcoming
    case completed
    case settings
    case detail(UUIDv7)

    public var title: String {
        switch self {
        case .panel: "Today"
        case .slimBar: "Today"
        case .hierarchy: "Hierarchy"
        case .upcoming: "Upcoming"
        case .completed: "Completed"
        case .settings: "Settings"
        case .detail: "Task"
        }
    }

    public var size: CGSize {
        switch self {
        case .panel: DesignTokens.Window.panel
        case .slimBar: DesignTokens.Window.slimBar
        case .hierarchy: DesignTokens.Window.hierarchy
        case .upcoming: DesignTokens.Window.upcoming
        case .completed: DesignTokens.Window.completed
        case .settings: DesignTokens.Window.settings
        case .detail: DesignTokens.Window.detail
        }
    }
}
