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
        // Deep link: the message text is often on the same pasteboard item.
        if let url = object.url, url.scheme?.lowercased() == "ms-outlook" {
            let headers = EmailHeaderParser.parse(object.text)
            return RecognizedObject(
                type: .email,
                displayName: headers.subject ?? "Outlook email",
                sourceApp: "outlook",
                reference: url.absoluteString,
                metadata: headers.metadata,
                suggestedTitle: headers.subject,
                previewText: object.text
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
            let headers = EmailHeaderParser.parse(object.text)
            return RecognizedObject(
                type: .email,
                displayName: headers.subject ?? "Mail message",
                sourceApp: sourceApp,
                reference: url.absoluteString,
                metadata: headers.metadata,
                suggestedTitle: headers.subject,
                previewText: object.text
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


/// Reads simple `Subject:` / `From:` / `To:` lines from the plain text that
/// Mail and Outlook put on the drag pasteboard alongside a message link.
enum EmailHeaderParser {
    struct Headers {
        var subject: String?
        var metadata: [String: String]
    }

    static func parse(_ text: String?) -> Headers {
        guard let text else { return Headers(subject: nil, metadata: [:]) }
        var subject: String?
        var metadata: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("subject:") {
                subject = String(trimmed.dropFirst("subject:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("from:") {
                metadata[MetadataKeys.from] = String(trimmed.dropFirst("from:".count))
                    .trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("to:") {
                metadata[MetadataKeys.to] = String(trimmed.dropFirst("to:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return Headers(subject: subject, metadata: metadata)
    }
}
