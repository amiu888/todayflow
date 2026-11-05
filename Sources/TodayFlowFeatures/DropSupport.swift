import Foundation
#if canImport(AppKit)
import AppKit
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
    ]
}
#endif
