import Foundation

/// Window-management commands surfaced inside the Today panel, so docking and
/// corner pinning are discoverable without hunting through the macOS menu bar.
public struct WindowMenuActions: Sendable {
    public var toggleDocking: @MainActor @Sendable () -> Void
    public var toggleAllDesktops: @MainActor @Sendable () -> Void
    public var toggleMiniCalendar: @MainActor @Sendable () -> Void
    public var showMiniDay: @MainActor @Sendable () -> Void
    public var showMiniWeek: @MainActor @Sendable () -> Void
    public var pinMiniCalendar: @MainActor @Sendable (ScreenCorner?) -> Void

    public init(
        toggleDocking: @escaping @MainActor @Sendable () -> Void,
        toggleAllDesktops: @escaping @MainActor @Sendable () -> Void,
        toggleMiniCalendar: @escaping @MainActor @Sendable () -> Void,
        showMiniDay: @escaping @MainActor @Sendable () -> Void,
        showMiniWeek: @escaping @MainActor @Sendable () -> Void,
        pinMiniCalendar: @escaping @MainActor @Sendable (ScreenCorner?) -> Void
    ) {
        self.toggleDocking = toggleDocking
        self.toggleAllDesktops = toggleAllDesktops
        self.toggleMiniCalendar = toggleMiniCalendar
        self.showMiniDay = showMiniDay
        self.showMiniWeek = showMiniWeek
        self.pinMiniCalendar = pinMiniCalendar
    }
}
