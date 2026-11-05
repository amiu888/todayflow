import Foundation

/// The parts of an email a summarizer needs. Built from a dropped message
/// (Outlook `.msg`/`.eml`, Apple Mail `.eml`/`message://`) or any source that
/// supplies a subject and body.
public struct EmailDigest: Hashable, Sendable {
    public var subject: String
    public var sender: String?
    public var recipients: String?
    public var body: String
    public var sourceApp: String?
    public var receivedAt: Date?

    public init(
        subject: String,
        sender: String? = nil,
        recipients: String? = nil,
        body: String = "",
        sourceApp: String? = nil,
        receivedAt: Date? = nil
    ) {
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.body = body
        self.sourceApp = sourceApp
        self.receivedAt = receivedAt
    }

    public var isEmpty: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// An AI summarizer. Implementations may be on-device (Apple Intelligence) or
/// a remote/local OpenAI-compatible endpoint. When no summarizer is available,
/// the app simply leaves `WorkItem.summary` empty.
public protocol EmailSummarizer: Sendable {
    func summarize(_ email: EmailDigest) async throws -> String
}
