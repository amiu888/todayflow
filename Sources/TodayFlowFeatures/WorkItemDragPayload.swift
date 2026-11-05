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
        let item = value as NSString
        let provider = NSItemProvider(
            item: item,
            typeIdentifier: UTType.todayFlowWorkItem.identifier
        )
        // A plain-text copy survives drag systems that drop custom UTIs.
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(value.utf8), nil)
            return nil
        }
        return provider
    }

    /// The pasteboard item written by the AppKit drag source. Keeping the
    /// value eager (not provider-backed) is what makes same-app drops reliable.
    public static func pasteboardItem(
        for itemId: UUIDv7,
        sourceTray: UUIDv7? = nil
    ) -> NSPasteboardItem {
        let value = sourceTray == nil
            ? itemId.uuid.uuidString
            : "\(itemId.uuid.uuidString)|\(sourceTray!.uuid.uuidString)"
        let item = NSPasteboardItem()
        item.setString(
            value,
            forType: NSPasteboard.PasteboardType(
                UTType.todayFlowWorkItem.identifier
            )
        )
        item.setString(value, forType: .string)
        return item
    }

    /// NSItemProvider is not Sendable, but a drop callback hands it to a
    /// MainActor task exactly once. This box makes that transfer explicit.
    public struct ProviderBox: @unchecked Sendable {
        public let provider: NSItemProvider

        public init(_ provider: NSItemProvider) {
            self.provider = provider
        }
    }

    /// Decodes anything a drag can hand us: the string provider used by
    /// `.onDrag`, Codable JSON from `.draggable`, or a plain-text copy.
    public static func payload(from item: NSSecureCoding?) -> WorkItemDragPayload? {
        if let string = (item as? String) ?? (item as? NSString).map(String.init) {
            if let decoded = decode(string) {
                return WorkItemDragPayload(
                    itemId: decoded.itemId,
                    sourceTrayId: decoded.sourceTray
                )
            }
            if let payload = try? JSONDecoder().decode(
                WorkItemDragPayload.self,
                from: Data(string.utf8)
            ) {
                return payload
            }
        }
        if let data = item as? Data {
            if let payload = try? JSONDecoder().decode(
                WorkItemDragPayload.self,
                from: data
            ) {
                return payload
            }
            if let string = String(data: data, encoding: .utf8),
               let decoded = decode(string)
            {
                return WorkItemDragPayload(
                    itemId: decoded.itemId,
                    sourceTrayId: decoded.sourceTray
                )
            }
        }
        return nil
    }

    /// Loads a payload from any encoding this app can produce.
    public static func load(from provider: NSItemProvider) async -> WorkItemDragPayload? {
        let type = UTType.todayFlowWorkItem.identifier
        if let value = try? await provider.loadItem(
            forTypeIdentifier: type,
            options: nil
        ) {
            if let payload = payload(from: value) { return payload }
        }
        if let value = try? await provider.loadItem(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            options: nil
        ) {
            return payload(from: value)
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
               let payload = payload(from: string as NSString)
            {
                payloads.append(payload)
                continue
            }
            if let data = item.data(forType: type),
               let payload = payload(from: data as NSData)
            {
                payloads.append(payload)
                continue
            }
            // Fallback for drag systems that only preserve plain text.
            if let string = item.string(forType: .string),
               let payload = payload(from: string as NSString)
            {
                payloads.append(payload)
            }
        }

        if payloads.isEmpty {
            let strings = pasteboard.readObjects(
                forClasses: [NSString.self],
                options: nil
            ) as? [NSString] ?? []
            for string in strings {
                if let payload = payload(from: string) {
                    payloads.append(payload)
                }
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
