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

/// Snaps floating TodayFlow windows after the user finishes dragging them.
@MainActor
public final class WindowDockController {
    public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.key)
        }
    }

    private static let key = "todayflow.dockToEdges"
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var isSnapping = false

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
        scheduleSnap(for: notification.object as? NSWindow)
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
        guard isEnabled, window.isVisible else { return }
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
