import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes emails from Outlook: `ms-outlook://` deep links, `.msg` files,
/// and `.eml` files whose source app is Outlook (driver.md §7).
public struct OutlookEmailRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let url = object.url {
            return url.scheme?.lowercased() == "ms-outlook"
        }
        if let file = object.fileURL {
            let ext = file.pathExtension.lowercased()
            if ext == "msg" { return true }
            if ext == "eml" {
                return (object.sourceApp ?? "").localizedCaseInsensitiveContains("outlook")
            }
        }
        return false
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        // Deep link: the app can only see the URL, not the message.
        if let url = object.url, url.scheme?.lowercased() == "ms-outlook" {
            return RecognizedObject(
                type: .email,
                displayName: "Outlook email",
                sourceApp: "outlook",
                reference: url.absoluteString
            )
        }

        let filename = object.fileURL?.lastPathComponent ?? "email"

        // Outlook saves messages as `.msg` (OLE compound files).
        if object.fileURL?.pathExtension.lowercased() == "msg", let data = object.fileData {
            if let message = MsgReader.read(data) {
                return RecognizedObject(
                    type: .email,
                    uti: object.uti?.identifier ?? "x-outlook-message",
                    displayName: message.subject ?? filename,
                    sourceApp: "outlook",
                    reference: object.fileURL?.path,
                    metadata: emailMetadata(message: message),
                    suggestedTitle: message.subject,
                    previewText: message.body
                )
            }
        }

        // `.eml` (RFC 822) from Outlook.
        if object.fileURL?.pathExtension.lowercased() == "eml", let data = object.fileData {
            let message = EmlParser.parse(data)
            return RecognizedObject(
                type: .email,
                uti: object.uti?.identifier ?? "org.rfc822-message",
                displayName: message.subject ?? filename,
                sourceApp: "outlook",
                reference: object.fileURL?.path,
                metadata: emailMetadata(
                    from: message.from,
                    to: message.to,
                    receivedAt: message.date,
                    messageId: message.messageId
                ),
                suggestedTitle: message.subject,
                previewText: message.body
            )
        }

        // Fallback when the file contents were not loaded.
        return RecognizedObject(
            type: .email,
            uti: object.uti?.identifier,
            displayName: filename,
            sourceApp: "outlook",
            reference: object.fileURL?.path
        )
    }

    private func emailMetadata(
        message: MsgMessage
    ) -> [String: String] {
        var metadata: [String: String] = [:]
        if let sender = message.sender { metadata[MetadataKeys.sender] = sender }
        if let receivedAt = message.deliveredAt {
            metadata[MetadataKeys.receivedAt] = Iso8601.encode(receivedAt)
        }
        if let messageId = message.messageId { metadata[MetadataKeys.messageId] = messageId }
        return metadata
    }

    private func emailMetadata(
        from: String?,
        to: String?,
        receivedAt: Date?,
        messageId: String?
    ) -> [String: String] {
        var metadata: [String: String] = [:]
        if let from { metadata[MetadataKeys.from] = from }
        if let to { metadata[MetadataKeys.to] = to }
        if let receivedAt { metadata[MetadataKeys.receivedAt] = Iso8601.encode(receivedAt) }
        if let messageId { metadata[MetadataKeys.messageId] = messageId }
        return metadata
    }
}

/// Recognizes emails from Apple Mail: `message://` links and `.eml` files from
/// any app that is not Outlook (driver.md §7).
public struct MailEmailRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let url = object.url {
            return url.scheme?.lowercased() == "message"
        }
        guard object.fileURL?.pathExtension.lowercased() == "eml" else { return false }
        let source = object.sourceApp ?? ""
        return !source.localizedCaseInsensitiveContains("outlook")
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        let sourceApp = object.sourceApp ?? "mail"
        let filename = object.fileURL?.lastPathComponent ?? "email"

        if let url = object.url, url.scheme?.lowercased() == "message" {
            return RecognizedObject(
                type: .email,
                displayName: "Mail message",
                sourceApp: sourceApp,
                reference: url.absoluteString
            )
        }

        if let data = object.fileData {
            let message = EmlParser.parse(data)
            return RecognizedObject(
                type: .email,
                uti: object.uti?.identifier ?? "org.rfc822-message",
                displayName: message.subject ?? filename,
                sourceApp: sourceApp,
                reference: object.fileURL?.path,
                metadata: [
                    MetadataKeys.from: message.from,
                    MetadataKeys.to: message.to,
                    MetadataKeys.receivedAt: message.date.map(Iso8601.encode),
                    MetadataKeys.messageId: message.messageId,
                ].compactMapValues { $0 },
                suggestedTitle: message.subject,
                previewText: message.body
            )
        }

        return RecognizedObject(
            type: .email,
            uti: object.uti?.identifier,
            displayName: filename,
            sourceApp: sourceApp,
            reference: object.fileURL?.path
        )
    }
}
