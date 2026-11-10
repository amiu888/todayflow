import Foundation

/// Reads the private drag data web pages attach with
/// `dataTransfer.setData("<custom/type>", ...)`.
///
/// Jira board and backlog cards are dragged with Atlassian's own drag library,
/// which stores the card in custom types instead of a URL or plain text. When
/// such a drag leaves the browser, Chrome puts it on the pasteboard as
/// `org.chromium.web-custom-data`: a Chromium "pickle" holding
/// `[(mime type, value)]` pairs as UTF-16 strings.
public enum WebCustomData {
    /// Pasteboard types that carry web custom data (Chrome/Edge/Arc/Brave, then
    /// Safari).
    public static let pasteboardTypes = [
        "org.chromium.web-custom-data",
        "chromium/x-web-custom-data",
        "com.apple.WebKit.custom-pasteboard-data",
    ]

    /// The `(type, value)` pairs in a Chromium pickle. Returns an empty array
    /// when the bytes are not in that format.
    public static func entries(from data: Data) -> [(type: String, value: String)] {
        var reader = PickleReader(bytes: [UInt8](data))
        guard let payloadSize = reader.uint32(),
              Int(payloadSize) <= data.count - 4,
              let count = reader.uint32(),
              count < 10_000
        else { return [] }
        var result: [(String, String)] = []
        for _ in 0..<count {
            guard let type = reader.string16(), let value = reader.string16() else { break }
            result.append((type, value))
        }
        return result
    }

    /// All readable text in the payload. Parses the Chromium format when it
    /// can and otherwise falls back to the UTF-16 and UTF-8 text inside, which
    /// covers Safari's format and future changes to Chrome's.
    public static func text(from data: Data) -> String {
        let parsed = entries(from: data)
        if !parsed.isEmpty {
            return parsed.map { "\($0.type)\n\($0.value)" }.joined(separator: "\n")
        }
        var pieces: [String] = []
        if let utf16 = String(data: data, encoding: .utf16LittleEndian) {
            pieces.append(printable(utf16))
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            pieces.append(printable(utf8))
        }
        return pieces.joined(separator: "\n")
    }

    /// A Jira issue URL found in the payload. When the card only names its
    /// key (for example `"issueKey":"ABC-123"`) and a Jira site appears
    /// anywhere in the data, the URL is built as `<site>/browse/<key>`.
    public static func jiraIssueURL(from data: Data) -> URL? {
        jiraIssueURL(inText: text(from: data))
    }

    /// The card's title from a JSON-ish payload (`"summary"` or `"title"`),
    /// used as the task title next to the issue key.
    public static func cardSummary(from data: Data) -> String? {
        let text = text(from: data)
        for field in ["summary", "title", "name"] {
            let pattern = "\"\(field)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.){2,300})\""
            if let raw = firstCapture(pattern, in: text) {
                let json = "\"\(raw)\""
                if let decoded = try? JSONDecoder().decode(String.self, from: Data(json.utf8)) {
                    return decoded
                }
                return raw
            }
        }
        return nil
    }

    static func jiraIssueURL(inText text: String) -> URL? {
        // JSON payloads escape slashes as `\/`.
        let unescaped = text.replacingOccurrences(of: "\\/", with: "/")
        if let url = JiraIssueReference.firstURL(in: unescaped) { return url }

        guard let key = firstIssueKey(in: unescaped),
              let site = firstJiraSite(in: unescaped),
              let url = URL(string: "\(site)/browse/\(key)")
        else { return nil }
        return JiraIssueReference(url: url) == nil ? nil : url
    }

    private static func firstIssueKey(in text: String) -> String? {
        // Prefer a key named as one (issueKey/key) over any key-shaped word.
        let patterns = [
            #"(?i)"?(?:issue_?key|key)"?\s*[:=]\s*"?([A-Z][A-Z0-9_]{0,19}-\d{1,7})(?![A-Za-z0-9])"#,
            #"(?<![A-Za-z0-9-])([A-Z][A-Z0-9_]{0,19}-\d{1,7})(?![A-Za-z0-9])"#,
        ]
        for pattern in patterns {
            if let match = firstCapture(pattern, in: text) { return match.uppercased() }
        }
        return nil
    }

    private static func firstJiraSite(in text: String) -> String? {
        let pattern = #"(https?://[A-Za-z0-9.-]*(?:atlassian\.net|jira[A-Za-z0-9.-]*)(?::\d+)?)"#
        return firstCapture(pattern, in: text)
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func printable(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar in
            scalar.properties.isWhitespace || (scalar.value >= 0x20 && scalar.value != 0x7F)
                ? Character(scalar) : " "
        })
    }
}

/// Minimal reader for Chromium's `base::Pickle`: little-endian 32-bit fields,
/// UTF-16 strings prefixed by their length in code units, each field padded
/// to 4 bytes.
private struct PickleReader {
    let bytes: [UInt8]
    var offset = 0

    mutating func uint32() -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        let value = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
        offset += 4
        return value
    }

    mutating func string16() -> String? {
        guard let length = uint32(), length < 5_000_000 else { return nil }
        let byteCount = Int(length) * 2
        guard offset + byteCount <= bytes.count else { return nil }
        let slice = Data(bytes[offset..<offset + byteCount])
        offset += (byteCount + 3) & ~3
        return String(data: slice, encoding: .utf16LittleEndian)
    }
}
