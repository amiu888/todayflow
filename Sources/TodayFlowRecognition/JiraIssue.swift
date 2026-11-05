import Foundation
import TodayFlowCore

/// A Jira issue link dragged from the web UI. Jira boards and issue pages
/// advertise ordinary web URLs, so the issue key is the reliable signal:
/// `/browse/ABC-123`, `/jira/.../browse/ABC-123`, or `?selectedIssue=ABC-123`.
public struct JiraIssueReference: Sendable, Hashable {
    public let issueKey: String
    public let projectKey: String
    public let url: URL

    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let issueKey = Self.issueKey(in: url)
        else { return nil }
        self.issueKey = issueKey
        self.projectKey = String(issueKey.split(separator: "-").first ?? "")
        self.url = url
    }

    /// The first Jira issue URL in a dropped text/HTML payload. Browser drags
    /// often provide only plain text, not `public.url`.
    public static func firstURL(in text: String) -> URL? {
        guard text.count <= 200_000 else { return nil }
        if let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                if let url = match.url, JiraIssueReference(url: url) != nil {
                    return url
                }
            }
        }
        // A bare URL inside a multi-line card may not be detected as a link.
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let cleaned = String(token).trimmingCharacters(
                in: CharacterSet(charactersIn: "<>\"'()[]{}.,;")
            )
            if let url = URL(string: cleaned), JiraIssueReference(url: url) != nil {
                return url
            }
        }
        return nil
    }

    /// A readable summary from the card's drag text. The first line is usually
    /// the issue summary; if it is only the key, the next line is used.
    public static func summary(from text: String?, issueKey: String) -> String? {
        guard let text else { return nil }
        let lines = text
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        for line in lines {
            if line.caseInsensitiveCompare(issueKey) == .orderedSame { continue }
            if line.lowercased().hasPrefix("http://")
                || line.lowercased().hasPrefix("https://")
            {
                continue
            }
            var candidate = line
            if let range = candidate.range(
                of: issueKey,
                options: [.caseInsensitive]
            ) {
                candidate.removeSubrange(range)
            }
            candidate = candidate.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(
                    CharacterSet(charactersIn: "·-–—:|/")
                )
            )
            if candidate.count >= 2 {
                return String(candidate.prefix(140))
            }
        }
        return nil
    }

    private static func issueKey(in url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                let name = item.name.lowercased()
                guard ["selectedissue", "issuekey", "issue", "key"].contains(name),
                      let value = item.value,
                      let key = normalizedKey(value)
                else { continue }
                return key
            }
        }

        let path = url.path
        if let browse = path.range(of: "/browse/", options: [.caseInsensitive]) {
            let tail = path[browse.upperBound...]
            let component = tail.split(separator: "/").first.map(String.init) ?? ""
            if let key = normalizedKey(component) { return key }
        }

        guard let regex = try? NSRegularExpression(
            pattern: "(?<![A-Za-z0-9])[A-Z][A-Z0-9_]{0,19}-\\d{1,7}(?![A-Za-z0-9])"
        ) else { return nil }
        let nsPath = path as NSString
        guard let match = regex.firstMatch(
            in: path,
            range: NSRange(location: 0, length: nsPath.length)
        ) else { return nil }
        return normalizedKey(nsPath.substring(with: match.range))
    }

    private static func normalizedKey(_ value: String) -> String? {
        let candidate = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let regex = try? NSRegularExpression(
            pattern: "^[A-Z][A-Z0-9_]{0,19}-\\d{1,7}$"
        ) else { return nil }
        let nsValue = candidate as NSString
        let range = NSRange(location: 0, length: nsValue.length)
        return regex.firstMatch(in: candidate, range: range) != nil ? candidate : nil
    }
}
