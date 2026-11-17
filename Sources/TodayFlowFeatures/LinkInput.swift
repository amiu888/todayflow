import Foundation

/// Turns what a person types into a link field into a URL.
public enum LinkInput {
    /// A usable web or app link, or `nil` when the text is not one.
    /// "example.com/page" becomes "https://example.com/page"; a link that
    /// already has a scheme (https, mailto, obsidian, …) is kept as typed.
    public static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "http" || scheme == "https" {
                return (url.host ?? "").isEmpty ? nil : url
            }
            // "localhost:3000" parses with scheme "localhost"; a real app
            // scheme is followed by more than a port number.
            let rest = trimmed.dropFirst(scheme.count + 1)
            if !rest.isEmpty, !rest.allSatisfy(\.isNumber), !rest.first!.isNumber {
                return url
            }
        }

        guard let url = URL(string: "https://" + trimmed),
              let host = url.host, !host.isEmpty,
              host.contains(".") || host == "localhost"
        else { return nil }
        return url
    }
}
