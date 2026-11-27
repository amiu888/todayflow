import Foundation

/// A ticket or change number found in a dropped object.
public struct TicketReference: Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case change, incident, problem, request, task, jira, ticket
    }

    /// As it should appear in the title: `CHG0012345`, `ABC-123`, `Ticket 48213`.
    public var id: String
    public var kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// The first reference in `texts`, most specific first: change numbers,
    /// then other ServiceNow records, Jira keys, then "Ticket 12345".
    public static func find(in texts: [String], jiraKey: String? = nil) -> TicketReference? {
        let joined = texts.joined(separator: "\n")
        if let match = first(#"\b(CHG|CTASK)\d{5,}\b"#, in: joined) { return .init(id: match.uppercased(), kind: .change) }
        if let match = first(#"\b(?:CR|RFC)[- ]?\d{3,}\b"#, in: joined, caseSensitive: true) {
            return .init(id: match, kind: .change)
        }
        if let number = group(#"\bchange(?:\s+request)?\s*(?:no\.?|number|#)?\s*:?\s*#?(\d{4,})\b"#, in: joined) {
            return .init(id: "Change \(number)", kind: .change)
        }
        for (prefix, kind) in [("INC", Kind.incident), ("PRB", .problem), ("RITM", .request), ("REQ", .request), ("SCTASK", .task)] {
            if let match = first(#"\b\#(prefix)\d{5,}\b"#, in: joined) { return .init(id: match.uppercased(), kind: kind) }
        }
        if let jiraKey, !jiraKey.isEmpty { return .init(id: jiraKey, kind: .jira) }
        // A Jira-style key only where it is clearly one, so UTF-8 or ISO-9001
        // never become "tickets": in a /browse/ link, in [brackets], or next
        // to the word Jira.
        if let key = group(#"/browse/([A-Z][A-Z0-9]{1,9}-\d+)\b"#, in: joined, caseSensitive: true)
            ?? group(#"\[([A-Z][A-Z0-9]{1,9}-\d+)\]"#, in: joined, caseSensitive: true)
            ?? (joined.range(of: "jira", options: .caseInsensitive) != nil
                ? group(#"\b([A-Z][A-Z0-9]{1,9}-\d+)\b"#, in: joined, caseSensitive: true) : nil)
        {
            return .init(id: key, kind: .jira)
        }
        if let number = group(#"\b(?:ticket|case|issue)\s*(?:no\.?|number|#)?\s*:?\s*#?(\d{4,})\b"#, in: joined) {
            return .init(id: "Ticket \(number)", kind: .ticket)
        }
        return nil
    }

    private static func first(_ pattern: String, in text: String, caseSensitive: Bool = false) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return String(text[range])
    }

    private static func group(_ pattern: String, in text: String, caseSensitive: Bool = false) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

/// Title rules shared by the plain capture and the AI suggestion.
public enum SmartTitle {
    /// The texts a reference may hide in, best first.
    public static func reference(for objects: [RecognizedObject]) -> TicketReference? {
        for object in objects {
            let texts = [
                object.suggestedTitle, object.displayName, object.reference,
                object.metadata["pageTitle"], object.metadata["jiraSummary"],
                object.previewText.map { String($0.prefix(1_500)) },
            ].compactMap { $0 }
            if let found = TicketReference.find(in: texts, jiraKey: object.metadata["jiraIssueKey"]) {
                return found
            }
        }
        return nil
    }

    /// "RE: FW: Budget for Q3" → "Budget for Q3"; long subjects are shortened.
    public static func cleanSubject(_ subject: String) -> String {
        var text = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = try? NSRegularExpression(pattern: #"^\s*((re|fw|fwd|aw|wg|tr|sv)\s*(\[\d+\])?\s*:\s*)+"#, options: [.caseInsensitive])
        if let prefix {
            text = prefix.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 90 {
            let cut = text.prefix(87)
            text = (cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)) + "…"
        }
        return text
    }

    /// Puts the reference at the front unless the title already has it:
    /// "Upgrade firewall" + CHG0012345 → "CHG0012345: Upgrade firewall".
    public static func withReference(_ title: String, _ reference: TicketReference?) -> String {
        guard let reference else { return title }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: reference.id, options: .caseInsensitive) != nil { return trimmed }
        if trimmed.isEmpty { return reference.id }
        return "\(reference.id): \(trimmed)"
    }

    /// An AI's title with the drop's real reference in front. A leading
    /// "CHG001: " or "ABC-12 - " that nothing in the drop contains was made
    /// up by the model, so it goes.
    public static func fromAI(_ title: String, objects: [RecognizedObject]) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\[?([A-Za-z]{2,8}[- ]?\d{2,}|#\d{3,})\]?\s*[:\-–]\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let prefixRange = Range(match.range(at: 1), in: text),
           let restRange = Range(match.range(at: 2), in: text) {
            let prefix = String(text[prefixRange])
            let source = objects.flatMap { object in
                [object.displayName, object.suggestedTitle ?? "", object.previewText ?? "", object.reference ?? ""]
                    + Array(object.metadata.values)
            }.joined(separator: "\n")
            if source.range(of: prefix, options: .caseInsensitive) == nil {
                text = String(text[restRange])
            }
        }
        return withReference(text, reference(for: objects))
    }

    /// The title a drop gets without AI.
    public static func inferredTitle(for objects: [RecognizedObject]) -> String? {
        guard let base = objects.lazy
            .compactMap({ $0.suggestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) ?? objects.first?.displayName
        else { return nil }
        let cleaned = objects.first?.type == .email ? cleanSubject(base) : base
        return withReference(cleaned, reference(for: objects))
    }

    /// Groups drops for learning: corrections to one kind (an Outlook email,
    /// a ServiceNow change, a link from one site) teach that kind only.
    public static func kindKey(for objects: [RecognizedObject]) -> String {
        guard let object = objects.first else { return "empty" }
        var parts = [object.type.rawValue]
        if let reference = reference(for: objects) { parts.append(reference.kind.rawValue) }
        if let source = object.sourceApp, !source.isEmpty { parts.append(source.lowercased()) }
        if object.type == .url || object.metadata["domain"] != nil {
            let host = object.metadata["domain"]
                ?? object.reference.flatMap { URL(string: $0)?.host }
            if let host { parts.append(host.lowercased().replacingOccurrences(of: "www.", with: "")) }
        }
        return parts.joined(separator: "|")
    }
}

/// A title and description the user saved for a drop, next to what was
/// suggested. Sent to the AI as examples for the same kind of drop.
public struct TitleExample: Codable, Hashable, Sendable {
    public var kindKey: String
    /// The object as the AI saw it (its name or subject).
    public var objectName: String
    public var suggestedTitle: String
    public var finalTitle: String
    public var suggestedDescription: String
    public var finalDescription: String
    public var at: Date

    public var corrected: Bool {
        suggestedTitle != finalTitle || suggestedDescription != finalDescription
    }

    public init(
        kindKey: String, objectName: String, suggestedTitle: String, finalTitle: String,
        suggestedDescription: String = "", finalDescription: String = "", at: Date = .now
    ) {
        self.kindKey = kindKey
        self.objectName = objectName
        self.suggestedTitle = suggestedTitle
        self.finalTitle = finalTitle
        self.suggestedDescription = suggestedDescription
        self.finalDescription = finalDescription
        self.at = at
    }
}

/// Remembers how the user titles and describes each kind of drop, in the
/// settings table (this Mac only). Corrections are kept first.
public actor TitleExampleStore {
    public static let settingKey = "ai_title_examples"
    public static let perKind = 12
    public static let total = 200

    private let settings: any SettingRepository

    public init(settings: any SettingRepository) {
        self.settings = settings
    }

    public func all() async -> [TitleExample] {
        guard let json = await settings.value(for: Self.settingKey),
              let examples = try? JSONDecoder.iso.decode([TitleExample].self, from: Data(json.utf8))
        else { return [] }
        return examples
    }

    public func record(_ example: TitleExample) async {
        var examples = await all()
        examples.insert(example, at: 0)
        var kept: [TitleExample] = []
        var counts: [String: Int] = [:]
        for item in examples {
            let count = counts[item.kindKey, default: 0]
            guard count < Self.perKind, kept.count < Self.total else { continue }
            counts[item.kindKey] = count + 1
            kept.append(item)
        }
        guard let data = try? JSONEncoder.iso.encode(kept) else { return }
        try? await settings.set(String(decoding: data, as: UTF8.self), for: Self.settingKey)
    }

    /// The best examples for a kind: corrections first, newest first.
    public func examples(for kindKey: String, limit: Int = 5) async -> [TitleExample] {
        let same = await all().filter { $0.kindKey == kindKey }
        let corrected = same.filter(\.corrected)
        let accepted = same.filter { !$0.corrected }
        return Array((corrected + accepted).prefix(limit))
    }

    public func clear() async {
        try? await settings.remove(Self.settingKey)
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
