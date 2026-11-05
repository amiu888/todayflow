#if canImport(AppKit)
import AppKit
import Foundation
import QuickLookUI
import UniformTypeIdentifiers
import TodayFlowCore

/// Opens, reveals, and Quick Looks attachments (driver.md FR-23).
///
/// Resolution order: the materialized copy, an absolute reference, a URL
/// reference, then a security-scoped bookmark. That covers transient email
/// copies, Finder files, web links, and persistent bookmarked files.
@MainActor
public final class AttachmentActions: NSObject {
    private let quickLookSource = QuickLookDataSource()

    public override init() {
        super.init()
    }

    public func url(for attachment: Attachment) -> URL? {
        if let path = attachment.localCopyPath, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let reference = attachment.reference, !reference.isEmpty {
            if reference.hasPrefix("/") {
                return URL(fileURLWithPath: reference)
            }
            if let url = URL(string: reference),
               let scheme = url.scheme?.lowercased(),
               ["http", "https", "file", "ms-outlook", "message", "msteams"].contains(scheme)
            {
                return url
            }
        }
        if let bookmark = attachment.bookmark {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return nil
    }

    /// The email client that should reopen an email attachment. Outlook drops
    /// carry `sourceApp = "outlook"`; Mail drops use `com.apple.mail` or a
    /// `message://` reference. Nil means "use the system default".
    public static func preferredEmailBundleIdentifier(
        for attachment: Attachment
    ) -> String? {
        guard attachment.kind == .email else { return nil }
        let source = (attachment.sourceApp ?? "").lowercased()
        if source.contains("outlook") {
            return "com.microsoft.outlook"
        }
        if source.contains("mail")
            || attachment.reference?.hasPrefix("message:") == true
        {
            return "com.apple.mail"
        }
        return nil
    }

    /// The extension an email copy needs for LaunchServices to treat it as a
    /// message. Older copies were named after the subject and lost their
    /// extension, so this also repairs those attachments on open.
    public static func emailFileExtension(for attachment: Attachment) -> String? {
        guard attachment.kind == .email else { return nil }
        let uti = (attachment.uti ?? attachment.metadata["drop_uti"] ?? "").lowercased()
        if uti.contains("outlook") || uti.contains("msg") { return "msg" }
        if uti.contains("rfc822") || uti.contains("eml")
            || uti.contains("email-message")
        {
            return "eml"
        }
        if uti.contains("calendar") || uti.contains("ics") { return "ics" }
        if let reference = attachment.reference {
            let ext = URL(fileURLWithPath: reference).pathExtension
            if !ext.isEmpty { return ext.lowercased() }
        }
        if let copy = attachment.localCopyPath {
            let ext = URL(fileURLWithPath: copy).pathExtension
            if !ext.isEmpty { return ext.lowercased() }
        }
        return nil
    }

    /// A file URL LaunchServices can identify. A legacy extension-less email
    /// copy is duplicated beside itself with the correct `.msg`/`.eml` suffix.
    private func openableURL(for attachment: Attachment) -> URL? {
        guard var url = url(for: attachment) else { return nil }
        guard url.isFileURL,
              url.pathExtension.isEmpty,
              let ext = Self.emailFileExtension(for: attachment)
        else { return url }
        let target = url.appendingPathExtension(ext)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.copyItem(at: url, to: target)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            url = target
        }
        return url
    }

    /// Opens the original with its default app (or the system handler for a
    /// web/deep-link URL). Excel files open in Excel, PDFs in Preview, etc.
    /// Email attachments reopen in the source client when it is installed.
    public func open(_ attachment: Attachment) {
        guard let url = openableURL(for: attachment) else {
            NSSound.beep()
            return
        }
        if let bundleId = Self.preferredEmailBundleIdentifier(for: attachment),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if error != nil {
                    NSSound.beep()
                }
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The display name of the default handler, e.g. “Microsoft Excel”.
    public func defaultApplicationName(for attachment: Attachment) -> String? {
        guard let url = openableURL(for: attachment), url.isFileURL,
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return nil }
        return FileManager.default.displayName(atPath: appURL.path)
    }

    /// Opens the attachment with a user-chosen application.
    public func chooseApplication(for attachment: Attachment) {
        guard let url = openableURL(for: attachment), url.isFileURL else {
            open(attachment)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Open “\(attachment.displayName)” with"
        panel.prompt = "Open With"
        panel.message = "Choose an application."
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let appURL = panel.url else { return }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if error != nil {
                NSSound.beep()
            }
        }
    }

    /// Reveals a file or folder in Finder.
    public func reveal(_ attachment: Attachment) {
        guard let url = url(for: attachment), url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Quick Look preview (Space in the detail window's attachment menu).
    public func quickLook(_ attachment: Attachment) {
        guard let url = openableURL(for: attachment), url.isFileURL else {
            open(attachment)
            return
        }
        guard let panel = QLPreviewPanel.shared() else { return }
        quickLookSource.previewURL = url
        panel.dataSource = quickLookSource
        panel.delegate = quickLookSource
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Quick Look's data source is not main-actor isolated in the SDK; keeping it
/// in a tiny AppKit-only object avoids an actor-isolated protocol conformance.
/// The panel always calls these methods on the main thread.
private final class QuickLookDataSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var previewURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        previewURL as NSURL?
    }
}
#endif
