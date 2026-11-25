import Foundation
#if canImport(AppKit)
#if canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

/// The pasteboard/drop types the Today panel accepts (driver.md FR-01/FR-06).
///
/// Kept in the features layer so the panel can advertise exactly the types its
/// host knows how to convert; the actual `NSItemProvider` → `DroppedObject`
/// conversion lives in TodayFlowMac.
public enum CaptureDropTypes {
    public static let supported: [UTType] = [
        .fileURL,
        .url,
        .image,
        .plainText,
        .html,
        .rtf,
    ] + webCustomData

    /// Private web drag data. Jira board/backlog cards only carry this when
    /// dragged out of Chrome or Safari, so without it the drop is refused.
    public static let webCustomData: [UTType] = [
        "org.chromium.web-custom-data",
        "chromium/x-web-custom-data",
        "com.apple.WebKit.custom-pasteboard-data",
    ].map { UTType(importedAs: $0) }
}
#endif
