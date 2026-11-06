import Foundation

/// Shared parsing for user-entered tags. Tags are free-form, but they are
/// trimmed, deduplicated case-insensitively, and kept short enough to read in
/// a row.
public enum TagName {
    public static let maximumLength = 40
    public static let maximumCount = 12

    /// Parses a comma- or semicolon-separated tag string.
    public static func parse(_ text: String) -> [String] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map(String.init)
        return normalize(parts)
    }

    /// Trims, drops empty tags, removes duplicates, and caps the list.
    public static func normalize(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Obsidian tags cannot contain spaces; keep the model portable by
            // storing the same hyphenated form the editor shows.
            let portable = trimmed.replacingOccurrences(
                of: "\\s+",
                with: "-",
                options: .regularExpression
            )
            let clipped = String(portable.prefix(maximumLength))
            let key = clipped.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(clipped)
            if result.count == maximumCount { break }
        }
        return result
    }

    /// The display form used in rows and menus.
    public static func display(_ tags: [String], limit: Int = 2) -> String {
        let visible = tags.prefix(limit).map { "#\($0)" }.joined(separator: " ")
        let extra = tags.count - min(tags.count, limit)
        return extra > 0 ? "\(visible) +\(extra)" : visible
    }
}
