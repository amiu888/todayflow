import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes Microsoft Teams messages: `msteams://` links, links to
/// `teams.microsoft.com`, and text copied from the Teams app (driver.md §7).
public struct TeamsMessageRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let url = object.url {
            if url.scheme?.lowercased() == "msteams" { return true }
            if url.host()?.contains("teams.microsoft.com") == true { return true }
        }
        if let text = object.text {
            if (object.sourceApp ?? "").localizedCaseInsensitiveContains("teams") {
                return true
            }
            let lower = text.lowercased()
            return lower.contains("teams.microsoft.com")
                || lower.contains("msteams://")
                || lower.contains("microsoft teams")
        }
        return false
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        if let url = object.url {
            return RecognizedObject(
                type: .teamsMessage,
                displayName: "Teams message",
                sourceApp: "teams",
                reference: url.absoluteString,
                metadata: [MetadataKeys.link: url.absoluteString]
            )
        }

        // Text copied from Teams, including the HTML/RTF cards that Teams
        // puts on the pasteboard.
        let text = object.text ?? ""
        let parsed = Self.parse(text)
        var metadata: [String: String] = parsed.metadata
        if let link = parsed.link {
            metadata[MetadataKeys.link] = link
        }
        return RecognizedObject(
            type: .teamsMessage,
            displayName: parsed.sender.map { "Teams · \($0)" } ?? "Teams message",
            sourceApp: object.sourceApp ?? "teams",
            reference: parsed.link,
            metadata: metadata,
            suggestedTitle: parsed.title,
            previewText: parsed.preview
        )
    }
}


private extension TeamsMessageRecognizer {
    struct Parsed {
        var title: String
        var preview: String
        var sender: String?
        var link: String?
        var metadata: [String: String]
    }

    /// Teams chat copies commonly look like:
    ///   Microsoft Teams
    ///   Jane Doe
    ///   10:30 AM
    ///   Can you review this?
    ///
    /// The HTML card can also flatten to plain text. Drop the chrome, keep the
    /// sender and message, and pull out a Teams link when present.
    static func parse(_ text: String) -> Parsed {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let chrome = Set(["microsoft teams", "teams", "chat", "channel"])
        var body = lines.filter { !chrome.contains($0.lowercased()) }

        let link = body.first {
            $0.contains("teams.microsoft.com") || $0.hasPrefix("msteams://")
        } ?? (text.contains("teams.microsoft.com") || text.contains("msteams://")
            ? firstURL(in: text)
            : nil)
        if let link {
            body.removeAll { $0 == link }
        }

        let timeRegex = try! NSRegularExpression(
            pattern: #"^\d{1,2}:\d{2}(\s?[AP]M)?$"#,
            options: [.caseInsensitive]
        )
        let timeIndex = body.firstIndex { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return timeRegex.firstMatch(in: line, range: range) != nil
        }

        var sender: String?
        if let timeIndex {
            if timeIndex > 0 {
                sender = body[timeIndex - 1]
            }
            body.remove(at: timeIndex)
            if sender != nil, timeIndex > 0 {
                body.remove(at: timeIndex - 1)
            }
        }
        // Remove any remaining time lines.
        body.removeAll { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return timeRegex.firstMatch(in: line, range: range) != nil
        }

        // Without a timestamp, only treat a Title Case name line as the sender;
        // ordinary message lines must keep their place as the title.
        if sender == nil, body.count > 1, looksLikeName(body[0]) {
            sender = body.removeFirst()
        }

        let message = body.joined(separator: "\n")
        let title = body.first.map { String($0.prefix(100)) }
            ?? sender.map { "Teams: \($0)" }
            ?? "Teams: channel/chat"
        var metadata: [String: String] = [:]
        if let sender { metadata[MetadataKeys.sender] = sender }
        if let link { metadata[MetadataKeys.link] = link }
        return Parsed(
            title: title,
            preview: message.isEmpty ? text : message,
            sender: sender,
            link: link,
            metadata: metadata
        )
    }

    static func looksLikeName(_ line: String) -> Bool {
        guard line.count <= 60,
              !line.contains("?"),
              !line.contains(".")
        else { return false }
        let words = line.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        return words.allSatisfy { $0.first?.isUppercase == true }
    }

    static func firstURL(in text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.firstMatch(in: text, range: range)?.url?.absoluteString
    }
}
