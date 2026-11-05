import SwiftUI
import UniformTypeIdentifiers
import TodayFlowCore
#if canImport(AppKit)
import AppKit
#endif

/// The app's exported UTType for dragging a work item between lists.
///
/// `UTType(exportedAs:)` works for in-app drag & drop without an Info.plist
/// declaration; adding `UTExportedTypeDeclarations` to the app target's
/// Info.plist is a 6.6 refinement (the package currently has no resources).
public extension UTType {
    static let todayFlowWorkItem = UTType(exportedAs: "com.todayflow.work-item")
}

/// The drag payload for a work item (driver.md FR-12 / FR-16: drag to reorder,
/// drag to reparent, drag to top level).
///
/// Shared by the Today list and the hierarchy — one payload type, one UTType,
/// so the two views can exchange drags and each decides what a drop means.
public struct WorkItemDragPayload: Codable, Transferable {
    public let itemId: UUIDv7
    /// Set when the drag began inside a tray, so dropping on another tray is a
    /// move rather than a copy.
    public let sourceTrayId: UUIDv7?

    public init(itemId: UUIDv7, sourceTrayId: UUIDv7? = nil) {
        self.itemId = itemId
        self.sourceTrayId = sourceTrayId
    }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .todayFlowWorkItem)
    }

    #if canImport(AppKit)
    /// The AppKit-backed drag source shared by Today, Upcoming, and trays.
    /// Using one provider implementation keeps every row draggable.
    @MainActor
    public static func itemProvider(
        for itemId: UUIDv7,
        sourceTray: UUIDv7? = nil
    ) -> NSItemProvider {
        let value = sourceTray == nil
            ? itemId.uuid.uuidString
            : "\(itemId.uuid.uuidString)|\(sourceTray!.uuid.uuidString)"
        return NSItemProvider(
            item: value as NSString,
            typeIdentifier: UTType.todayFlowWorkItem.identifier
        )
    }

    /// NSItemProvider is not Sendable, but a drop callback hands it to a
    /// MainActor task exactly once. This box makes that transfer explicit.
    public struct ProviderBox: @unchecked Sendable {
        public let provider: NSItemProvider

        public init(_ provider: NSItemProvider) {
            self.provider = provider
        }
    }

    /// Loads a payload from either encoding this app can produce: the string
    /// provider used by `.onDrag`, or the Codable JSON used by `.draggable`.
    /// Accepting both keeps every drop target working during migrations.
    public static func load(from provider: NSItemProvider) async -> WorkItemDragPayload? {
        let value = try? await provider.loadItem(
            forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
            options: nil
        )
        if let string = (value as? String) ?? (value as? NSString).map(String.init),
           let decoded = decode(string)
        {
            return WorkItemDragPayload(
                itemId: decoded.itemId,
                sourceTrayId: decoded.sourceTray
            )
        }
        if let data = value as? Data,
           let payload = try? JSONDecoder().decode(
                WorkItemDragPayload.self,
                from: data
           )
        {
            return payload
        }
        return nil
    }

    /// Snapshots every payload on the drag pasteboard. Drop callbacks must
    /// read this synchronously: an `NSItemProvider` handed to us by the drag
    /// system can be invalidated as soon as the callback returns, which made
    /// drops appear to be accepted and then silently do nothing.
    public static func loadAll(from pasteboard: NSPasteboard) -> [WorkItemDragPayload] {
        var payloads: [WorkItemDragPayload] = []
        let type = NSPasteboard.PasteboardType(UTType.todayFlowWorkItem.identifier)

        for item in pasteboard.pasteboardItems ?? [] {
            if let string = item.string(forType: type),
               let decoded = decode(string)
            {
                payloads.append(
                    WorkItemDragPayload(
                        itemId: decoded.itemId,
                        sourceTrayId: decoded.sourceTray
                    )
                )
                continue
            }

            if let data = item.data(forType: type),
               let payload = try? JSONDecoder().decode(
                    WorkItemDragPayload.self,
                    from: data
               )
            {
                payloads.append(payload)
            }
        }
        return payloads
    }

    /// The common case: the in-app drag pasteboard.
    public static func loadFromDragPasteboard() -> [WorkItemDragPayload] {
        loadAll(from: NSPasteboard(name: .drag))
    }

    /// Parses the provider string into the item and, when the drag started in
    /// a tray, its source tray (for move-between-trays).
    public static func decode(_ value: String) -> (itemId: UUIDv7, sourceTray: UUIDv7?)? {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard let first = parts.first, let uuid = UUID(uuidString: first) else {
            return nil
        }
        let source = parts.count > 1
            ? UUID(uuidString: parts[1]).map(UUIDv7.init)
            : nil
        return (UUIDv7(uuid), source)
    }
    #endif
}
