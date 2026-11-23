import AppKit

/// Remembers the size people resize a window to, so it opens at that size
/// next time. Only the size: each window still decides where it opens.
@MainActor
enum WindowSizeMemory {
    private static let prefix = "todayflow.size."
    private static var observer: NSObjectProtocol?

    static func key(_ name: String) -> String { prefix + name }

    /// Makes `window` resizable down to `minimum`, opens it at its last
    /// size, and remembers the next resize.
    static func makeResizable(_ window: NSWindow, name: String, minimum: NSSize) {
        window.styleMask.insert(.resizable)
        window.contentMinSize = minimum
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        track(window, name: name)
        restore(window, name: name)
    }

    /// Marks `window` so its size is saved after the user resizes it.
    static func track(_ window: NSWindow, name: String) {
        window.identifier = NSUserInterfaceItemIdentifier(key(name))
        installObserver()
    }

    /// Applies the saved content size, kept between the window's minimum and
    /// the screen it will open on.
    static func restore(_ window: NSWindow, name: String, defaults: UserDefaults = .standard) {
        guard let raw = defaults.string(forKey: key(name)) else { return }
        let saved = NSSizeFromString(raw)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame.size
        window.setContentSize(clamped(saved, minimum: window.contentMinSize, screen: screen))
    }

    static func clamped(_ size: NSSize, minimum: NSSize, screen: NSSize?) -> NSSize {
        var width = max(size.width, minimum.width)
        var height = max(size.height, minimum.height)
        if let screen {
            // Leave room for the title bar.
            width = min(width, max(minimum.width, screen.width))
            height = min(height, max(minimum.height, screen.height - 28))
        }
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    private static func installObserver() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndLiveResizeNotification, object: nil, queue: .main
        ) { note in
            // Posted on the main thread (queue: .main).
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated {
                guard let window = object as? NSWindow,
                      let id = window.identifier?.rawValue, id.hasPrefix(prefix)
                else { return }
                let size = window.contentRect(forFrameRect: window.frame).size
                UserDefaults.standard.set(NSStringFromSize(size), forKey: id)
            }
        }
    }
}
