#if canImport(AppKit)
import AppKit

/// The app's floating windows (driver.md lines 145-152).
///
/// Two shapes share the panel behavior: the main 360×640 panel (titled,
/// resizable) and the 360×44 slim bar (borderless, fixed size). Both float
/// above other apps' windows without stealing focus from the app the user was
/// working in, and both stay on every desktop and in full-screen spaces.
public final class PanelWindow: NSPanel {
    /// The two panel shapes (driver.md lines 145-152).
    public enum Style {
        /// The main window: titled, closable, resizable.
        case panel
        /// The slim bar: borderless, fixed size, dragged by its background.
        case slimBar
        /// The quick-add sheet: borderless, fixed size, dragged by its header.
        case capture
    }

    public init(contentRect: NSRect, style: Style) {
        let mask: NSWindow.StyleMask
        switch style {
        case .panel:
            mask = [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel]
        case .slimBar, .capture:
            mask = [.borderless, .nonactivatingPanel]
        }
        super.init(contentRect: contentRect, styleMask: mask, backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        switch style {
        case .panel:
            titleVisibility = .visible
            isMovableByWindowBackground = true
        case .slimBar, .capture:
            isMovableByWindowBackground = true
            // Let the SwiftUI material card define the shape instead of
            // showing an opaque square borderless window.
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
        }
    }

    /// A non-activating panel still needs to accept keyboard input for the
    /// capture field, the task rows, and the slim bar's tap target.
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}
#endif
