#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// Pure snapping geometry, separated so it can be unit-tested without windows.
public enum WindowDockGeometry {
    /// Returns the frame snapped to the nearest screen edge or neighbouring
    /// window edge. A frame that is not near anything is returned unchanged.
    public static func snapped(
        _ frame: CGRect,
        within screen: CGRect,
        others: [CGRect] = [],
        threshold: CGFloat = 14
    ) -> CGRect {
        var result = frame

        // Adjacent windows: snap beside / above / below a neighbour when the
        // two are nearly touching. Align shared edges when close.
        for other in others where other.width > 60 && other.height > 40 {
            let verticalOverlap = result.minY < other.maxY && result.maxY > other.minY
            let horizontalOverlap = result.minX < other.maxX && result.maxX > other.minX

            if verticalOverlap {
                if abs(result.minX - other.maxX) <= threshold {
                    result.origin.x = other.maxX
                } else if abs(result.maxX - other.minX) <= threshold {
                    result.origin.x = other.minX - result.width
                } else if abs(result.minX - other.minX) <= threshold {
                    result.origin.x = other.minX
                } else if abs(result.maxX - other.maxX) <= threshold {
                    result.origin.x = other.maxX - result.width
                }
            }

            if horizontalOverlap {
                if abs(result.maxY - other.minY) <= threshold {
                    result.origin.y = other.minY - result.height
                } else if abs(result.minY - other.maxY) <= threshold {
                    result.origin.y = other.maxY
                } else if abs(result.minY - other.minY) <= threshold {
                    result.origin.y = other.minY
                } else if abs(result.maxY - other.maxY) <= threshold {
                    result.origin.y = other.maxY - result.height
                }
            }
        }

        // Screen edges win only where the window is already close to one.
        if abs(result.minX - screen.minX) <= threshold {
            result.origin.x = screen.minX
        } else if abs(result.maxX - screen.maxX) <= threshold {
            result.origin.x = screen.maxX - result.width
        }

        if abs(result.minY - screen.minY) <= threshold {
            result.origin.y = screen.minY
        } else if abs(result.maxY - screen.maxY) <= threshold {
            result.origin.y = screen.maxY - result.height
        }

        return result
    }
}

/// The edge of another app's window the Today panel attaches to.
public enum DockEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case top
    case bottom

    public var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

/// A running application the panel is docked to.
public struct DockTarget: Codable, Equatable, Sendable {
    public var bundleId: String
    public var name: String
    public var edge: DockEdge

    public init(bundleId: String, name: String, edge: DockEdge) {
        self.bundleId = bundleId
        self.name = name
        self.edge = edge
    }
}

/// Pure application-docking geometry, testable without windows.
public enum AppDockGeometry {
    /// The panel frame attached to one edge of `target`, clamped to the screen.
    public static func dockedFrame(
        panelSize: CGSize,
        target: CGRect,
        edge: DockEdge,
        screen: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        var origin: CGPoint
        switch edge {
        case .left:
            origin = CGPoint(x: target.minX - panelSize.width - gap, y: target.maxY - panelSize.height)
        case .right:
            origin = CGPoint(x: target.maxX + gap, y: target.maxY - panelSize.height)
        case .top:
            origin = CGPoint(x: target.midX - panelSize.width / 2, y: target.maxY + gap)
        case .bottom:
            origin = CGPoint(x: target.midX - panelSize.width / 2, y: target.minY - panelSize.height - gap)
        }

        origin.x = min(max(origin.x, screen.minX), screen.maxX - panelSize.width)
        origin.y = min(max(origin.y, screen.minY), screen.maxY - panelSize.height)
        return CGRect(origin: origin, size: panelSize)
    }
}

/// Places a newly opened window beside the Today panel. The right side is
/// preferred; when the window does not fit there, the left side is used. If
/// neither side has room, the window is pinned to the side with more space so
/// it stays fully on screen.
public enum WindowOpeningLayout {
    public static func frame(
        size: CGSize,
        panel: CGRect?,
        screen: CGRect,
        gap: CGFloat = 8
    ) -> CGRect? {
        guard let panel else { return nil }

        let width = min(size.width, screen.width)
        let height = min(size.height, screen.height)
        let maxY = max(screen.minY, screen.maxY - height)
        let y = min(max(panel.maxY - height, screen.minY), maxY)

        let rightX = panel.maxX + gap
        if rightX + width <= screen.maxX {
            return CGRect(x: rightX, y: y, width: width, height: height)
        }

        let leftX = panel.minX - gap - width
        if leftX >= screen.minX {
            return CGRect(x: leftX, y: y, width: width, height: height)
        }

        // Neither side fits (for example, a very wide window or a centered
        // panel). Keep the window visible on the roomier side.
        let rightSpace = screen.maxX - panel.maxX
        let leftSpace = panel.minX - screen.minX
        let fallbackX = rightSpace >= leftSpace
            ? screen.maxX - width
            : screen.minX
        return CGRect(x: fallbackX, y: y, width: width, height: height)
    }
}

/// Places a standard window beside TodayFlow's main panel. Kept here so the
/// separate window controllers (Settings-adjacent AI windows, plan, ask,
/// review) use exactly the same rule as WindowManager.
@MainActor
public enum WindowPlacement {
    public static func besideMainWindow(_ window: NSWindow, main: NSWindow?) {
        let screen = main?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        guard let screen,
              let frame = WindowOpeningLayout.frame(
                  size: window.frame.size,
                  panel: main?.frame,
                  screen: screen
              )
        else {
            window.center()
            return
        }
        window.setFrame(frame, display: false)
    }
}

/// A pure left-to-right layout for tray windows attached to the panel.
public enum TrayWindowLayout {
    public static func frame(
        size: CGSize,
        panel: CGRect?,
        existing: [CGRect],
        screen: CGRect,
        gap: CGFloat = 8
    ) -> CGRect {
        let anchor = existing.max { lhs, rhs in
            if lhs.maxX == rhs.maxX {
                // Prefer the window on the lower row when a row is full.
                return lhs.maxY > rhs.maxY
            }
            return lhs.maxX < rhs.maxX
        } ?? panel
        guard let anchor else {
            return CGRect(
                x: screen.maxX - size.width - 24,
                y: screen.maxY - size.height - 24,
                width: size.width,
                height: size.height
            )
        }

        var origin = CGPoint(
            x: anchor.maxX + gap,
            y: anchor.maxY - size.height
        )
        if origin.x + size.width > screen.maxX {
            // No room to the right: stack a new row below the anchor.
            origin = CGPoint(
                x: min(anchor.minX, screen.maxX - size.width),
                y: anchor.minY - size.height - gap
            )
        }
        if origin.y < screen.minY {
            origin.y = screen.minY
        }
        if origin.x < screen.minX {
            origin.x = screen.minX
        }
        if origin.x + size.width > screen.maxX {
            origin.x = screen.maxX - size.width
        }
        if origin.y + size.height > screen.maxY {
            origin.y = screen.maxY - size.height
        }
        return CGRect(origin: origin, size: size)
    }
}

/// Snaps floating TodayFlow windows after the user finishes dragging them.
@MainActor
public final class WindowDockController {
    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
        }
    }

    private static let key = "todayflow.dockToEdges"
    private static let appTargetKey = "todayflow.dockedApp"
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var isSnapping = false

    /// The app the panel is attached to, if any.
    public private(set) var dockedTarget: DockTarget?
    private weak var dockedPanel: NSWindow?
    private var followTask: Task<Void, Never>?

    public var isDockedToApp: Bool { dockedTarget != nil }

    public init() {
        if UserDefaults.standard.object(forKey: Self.key) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.key)
        }

        // Selector-based observers do not retain `self`, so no deinit removal
        // is needed (which would be nonisolated under Swift 6).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: nil
        )
    }

    @objc private func windowDidMove(_ notification: Notification) {
        guard dockedTarget == nil else { return }
        scheduleSnap(for: notification.object as? NSWindow)
    }

    // MARK: - Application docking

    /// Attaches the panel to one edge of the running app's front window.
    /// Defaults to the left edge; the panel follows the app window while docked.
    public func dock(
        panel: NSWindow,
        bundleId: String,
        appName: String,
        edge: DockEdge = .left
    ) {
        dockedPanel = panel
        dockedTarget = DockTarget(bundleId: bundleId, name: appName, edge: edge)
        persistTarget()
        startFollowing()
        // Dock is an explicit action; place the panel now even though
        // TodayFlow is frontmost while the popover is open.
        repositionDockedPanel(force: true)
    }

    /// Changes the attachment edge without undocking.
    public func setDockEdge(_ edge: DockEdge) {
        guard var target = dockedTarget else { return }
        target.edge = edge
        dockedTarget = target
        persistTarget()
        repositionDockedPanel(force: true)
    }

    /// Detaches from the other app and re-enables edge snapping.
    public func undock() {
        followTask?.cancel()
        followTask = nil
        dockedTarget = nil
        dockedPanel = nil
        UserDefaults.standard.removeObject(forKey: Self.appTargetKey)
    }

    /// Restores the last docked app when the panel is shown again, if that app
    /// is still running.
    public func restoreIfNeeded(panel: NSWindow) {
        guard dockedTarget == nil,
              let data = UserDefaults.standard.data(forKey: Self.appTargetKey),
              let saved = try? JSONDecoder().decode(DockTarget.self, from: data),
              NSRunningApplication.runningApplications(
                withBundleIdentifier: saved.bundleId
              ).first != nil
        else { return }
        dockedPanel = panel
        dockedTarget = saved
        startFollowing()
        repositionDockedPanel(force: true)
    }

    private func persistTarget() {
        guard let dockedTarget,
              let data = try? JSONEncoder().encode(dockedTarget)
        else { return }
        UserDefaults.standard.set(data, forKey: Self.appTargetKey)
    }

    private func startFollowing() {
        followTask?.cancel()
        followTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.repositionDockedPanel()
                // 30 Hz is smooth enough for window following without
                // enumerating the window server on every display refresh.
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func repositionDockedPanel(force: Bool = false) {
        guard let target = dockedTarget,
              let panel = dockedPanel,
              panel.isVisible,
              let running = NSRunningApplication.runningApplications(
                withBundleIdentifier: target.bundleId
              ).first
        else { return }
        // During normal following, do not chase another app's window while
        // the user is working in TodayFlow's own panel. An explicit Dock
        // action forces the first placement.
        if !force,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier != target.bundleId
        {
            return
        }
        guard let appFrame = Self.frontWindowFrame(for: running.processIdentifier)
        else { return }
        let screen = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let frame = AppDockGeometry.dockedFrame(
            panelSize: panel.frame.size,
            target: appFrame,
            edge: target.edge,
            screen: screen
        )
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    /// The app's frontmost on-screen window in AppKit coordinates.
    static func frontWindowFrame(for pid: pid_t) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        for info in raw {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t,
                  owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 180,
                  rect.height > 120
            else { continue }
            return CGRect(
                x: rect.minX,
                y: primaryHeight - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        return nil
    }

    private func scheduleSnap(for window: NSWindow?) {
        guard isEnabled, !isSnapping, let window, window is PanelWindow else { return }
        let key = ObjectIdentifier(window)
        pending[key]?.cancel()
        pending[key] = Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, let window else { return }
            self.snap(window)
            self.pending[key] = nil
        }
    }

    private func snap(_ window: NSWindow) {
        guard isEnabled, dockedTarget == nil, window.isVisible else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }

        let current = window.frame
        let appWindows = NSApp.windows
            .filter {
                $0 !== window
                    && $0.isVisible
                    && !$0.isMiniaturized
                    && $0.frame.width > 80
                    && $0.frame.height > 60
            }
            .map(\.frame)
        let external = externalWindowFrames()

        let target = WindowDockGeometry.snapped(
            current,
            within: screen.visibleFrame,
            others: appWindows + external
        )
        guard target != current else { return }

        isSnapping = true
        window.setFrame(target, display: true, animate: true)
        isSnapping = false
    }

    /// Other apps' on-screen windows, converted from Quartz's top-left global
    /// coordinates to AppKit's bottom-left coordinates.
    private func externalWindowFrames() -> [CGRect] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }

        return raw.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 80,
                  rect.height > 60
            else { return nil }

            return CGRect(
                x: rect.minX,
                y: primaryHeight - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
    }
}
#endif
