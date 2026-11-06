import CoreGraphics
import Foundation

/// The collapsible regions of the Today panel, in visual order.
public enum TodayPanelSection: String, CaseIterable, Sendable, Hashable {
    case week
    case trays
    case overdue
    case today
    case upcoming
    case done
}

/// Decides which sections fold away as the panel gets shorter. The day's open
/// tasks (`today`) are never folded automatically; the panel gives space back
/// from the bottom up, then from the top.
public enum TodaySectionCollapsePolicy {
    /// Height thresholds are deliberately spread apart so a resize does not
    /// flicker several sections open and closed at once.
    public static let doneThreshold: CGFloat = 620
    public static let upcomingThreshold: CGFloat = 560
    public static let traysThreshold: CGFloat = 500
    public static let weekThreshold: CGFloat = 450
    public static let overdueThreshold: CGFloat = 430

    public static func autoCollapsed(
        forHeight height: CGFloat,
        hasDone: Bool = true,
        hasUpcoming: Bool = true,
        hasOverdue: Bool = true
    ) -> Set<TodayPanelSection> {
        var sections: Set<TodayPanelSection> = []

        if hasDone, height < doneThreshold {
            sections.insert(.done)
        }
        if hasUpcoming, height < upcomingThreshold {
            sections.insert(.upcoming)
        }
        if height < traysThreshold {
            sections.insert(.trays)
        }
        if height < weekThreshold {
            sections.insert(.week)
        }
        if hasOverdue, height < overdueThreshold {
            sections.insert(.overdue)
        }

        return sections
    }
}
