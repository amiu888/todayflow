import AppKit
import TodayFlowCore

/// macOS 15.4+ lets the user block an app from reading the clipboard
/// (System Settings ▸ Privacy & Security ▸ Paste from Other Apps). TodayFlow
/// reads the clipboard itself on ⌘V, so a "Deny" there makes paste silently
/// attach nothing. This explains it instead.
@MainActor
enum ClipboardAccess {
    /// A short name for the current access setting, for the log.
    static func behaviorName(_ pasteboard: NSPasteboard = .general) -> String {
        guard #available(macOS 15.4, *) else { return "n/a" }
        switch pasteboard.accessBehavior {
        case .default: return "default"
        case .ask: return "ask"
        case .alwaysAllow: return "allow"
        case .alwaysDeny: return "deny"
        @unknown default: return "unknown"
        }
    }

    static func isDenied(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard #available(macOS 15.4, *) else { return false }
        return pasteboard.accessBehavior == .alwaysDeny
    }

    /// Call when a paste found nothing it could read. Returns true when the
    /// alert was shown, so the caller consumes the key.
    static func explainIfBlocked(_ pasteboard: NSPasteboard = .general) -> Bool {
        let behavior = behaviorName(pasteboard)
        Diagnostics.log("paste", "clipboard unreadable access=\(behavior)")
        guard isDenied(pasteboard) else { return false }
        let alert = NSAlert()
        alert.messageText = "TodayFlow can’t read the clipboard"
        alert.informativeText = """
        macOS is set to deny TodayFlow access to copied items, so screenshots \
        and files can’t be pasted into tasks.

        Open System Settings ▸ Privacy & Security ▸ Paste from Other Apps and \
        set TodayFlow to Allow.
        """
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        {
            NSWorkspace.shared.open(url)
        }
        return true
    }
}
