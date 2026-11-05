#if canImport(AppKit)
import AppKit
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

public extension UTType {
    static let todayFlowContact = UTType(exportedAs: "com.todayflow.contact")
}

/// Internal drag payload for moving a contact between groups. The source group
/// is included so a drop from one group to another is a move, while a drag from
/// All Contacts is an add.
public struct ContactDragPayload: Sendable, Hashable {
    public let contactId: UUIDv7
    public let sourceGroupId: UUIDv7?

    public init(contactId: UUIDv7, sourceGroupId: UUIDv7?) {
        self.contactId = contactId
        self.sourceGroupId = sourceGroupId
    }

    @MainActor
    public func itemProvider() -> NSItemProvider {
        let value = sourceGroupId == nil
            ? contactId.uuid.uuidString
            : "\(contactId.uuid.uuidString)|\(sourceGroupId!.uuid.uuidString)"
        return NSItemProvider(
            item: value as NSString,
            typeIdentifier: UTType.todayFlowContact.identifier
        )
    }

    public static func decode(_ value: String) -> ContactDragPayload? {
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        guard let first = parts.first, let uuid = UUID(uuidString: first) else {
            return nil
        }
        let source = parts.count > 1
            ? UUID(uuidString: parts[1]).map(UUIDv7.init)
            : nil
        return ContactDragPayload(contactId: UUIDv7(uuid), sourceGroupId: source)
    }

    @MainActor
    public static func loadAll(from providers: [NSItemProvider]) async -> [ContactDragPayload] {
        var payloads: [ContactDragPayload] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(
                UTType.todayFlowContact.identifier
            ) else { continue }
            let string: String? = await withCheckedContinuation { continuation in
                provider.loadItem(
                    forTypeIdentifier: UTType.todayFlowContact.identifier,
                    options: nil
                ) { item, _ in
                    if let value = item as? String {
                        continuation.resume(returning: value)
                    } else if let value = item as? NSString {
                        continuation.resume(returning: value as String)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
            if let string, let payload = decode(string) {
                payloads.append(payload)
            }
        }
        return payloads
    }
}
#endif
