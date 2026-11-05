#if canImport(AppKit)
import AppKit
import Foundation
import QuickLookUI
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

    /// Opens the original with its default app (or the system handler for a
    /// web/deep-link URL).
    public func open(_ attachment: Attachment) {
        guard let url = url(for: attachment) else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Reveals a file or folder in Finder.
    public func reveal(_ attachment: Attachment) {
        guard let url = url(for: attachment), url.isFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Quick Look preview (Space in the detail window's attachment menu).
    public func quickLook(_ attachment: Attachment) {
        guard let url = url(for: attachment), url.isFileURL else {
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
