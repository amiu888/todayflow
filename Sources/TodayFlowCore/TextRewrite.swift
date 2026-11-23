import Foundation

/// One request in a rewrite conversation and what the AI answered.
public struct RewriteTurn: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// What the person asked for ("More formal", "mention Friday").
    public var request: String
    /// The rewritten text, once the AI answers.
    public var text: String?
    /// The AI's short comment or suggestions, if it gave any.
    public var note: String?
    /// What the chat shows for the request ("More formal"), if not `request`.
    public var label: String?

    public init(id: UUID = UUID(), request: String, text: String? = nil, note: String? = nil, label: String? = nil) {
        self.id = id
        self.request = request
        self.text = text
        self.note = note
        self.label = label
    }

    public var displayRequest: String { label ?? request }
}

/// Rewrites text in a back-and-forth conversation: each turn refines the
/// previous version.
public protocol TextRewriting: Sendable {
    /// `conversation` ends with the newest request (its `text` is nil).
    func rewrite(_ original: String, conversation: [RewriteTurn]) async throws -> RewriteReply
}

/// The AI's answer: the new version, plus an optional short comment.
public struct RewriteReply: Hashable, Sendable {
    public var text: String
    public var note: String?

    public init(text: String, note: String? = nil) {
        self.text = text
        self.note = note
    }

    /// Reads a reply in the `NOTE: … / TEXT: …` format. A reply without the
    /// labels is all text. Reasoning blocks (`<think>…</think>`) are dropped.
    public static func parse(_ raw: String) -> RewriteReply {
        var body = raw.replacingOccurrences(
            of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression
        )
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // A reply wrapped in a code fence.
        if body.hasPrefix("```"), body.hasSuffix("```"), body.count > 6 {
            body = String(body.dropFirst(3).dropLast(3))
            if let newline = body.firstIndex(of: "\n"), !body[..<newline].contains(" ") {
                body = String(body[body.index(after: newline)...])
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let textRange = body.range(of: #"(?m)^\s*TEXT:\s*"#, options: .regularExpression) else {
            let note = body.range(of: #"(?m)^\s*NOTE:"#, options: .regularExpression)
            if note != nil {
                // Only a note: keep the line as the note, nothing to rewrite.
                let cleaned = body.replacingOccurrences(of: #"(?m)^\s*NOTE:\s*"#, with: "", options: .regularExpression)
                return RewriteReply(text: "", note: cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return RewriteReply(text: body)
        }
        let text = String(body[textRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var note: String?
        let head = String(body[..<textRange.lowerBound])
        if let noteRange = head.range(of: #"(?m)^\s*NOTE:\s*"#, options: .regularExpression) {
            let value = String(head[noteRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, value.lowercased() != "none" { note = value }
        }
        return RewriteReply(text: text, note: note)
    }
}

/// One-click styles shown as chips above the chat box.
public enum RewritePreset: String, CaseIterable, Identifiable, Sendable {
    case fixGrammar, formal, friendly, shorter, clearer, bullets, longer, suggest

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fixGrammar: "Fix grammar"
        case .formal: "More formal"
        case .friendly: "Friendlier"
        case .shorter: "Shorter"
        case .clearer: "Clearer"
        case .bullets: "Bullet points"
        case .longer: "More detail"
        case .suggest: "Suggest improvements"
        }
    }

    public var symbol: String {
        switch self {
        case .fixGrammar: "checkmark.seal"
        case .formal: "briefcase"
        case .friendly: "face.smiling"
        case .shorter: "arrow.down.right.and.arrow.up.left"
        case .clearer: "lightbulb"
        case .bullets: "list.bullet"
        case .longer: "text.append"
        case .suggest: "text.bubble"
        }
    }

    /// What is sent to the AI.
    public var request: String {
        switch self {
        case .fixGrammar: "Fix spelling, grammar and punctuation only. Keep everything else."
        case .formal: "Make it more formal and professional."
        case .friendly: "Make it warmer and friendlier, still professional."
        case .shorter: "Make it shorter and more concise. Keep every fact."
        case .clearer: "Make it clearer and easier to follow."
        case .bullets: "Turn it into a short bullet list."
        case .longer: "Add a little more detail and context, without inventing facts."
        case .suggest: "Point out what could be improved in the NOTE, and apply those improvements in TEXT."
        }
    }
}
