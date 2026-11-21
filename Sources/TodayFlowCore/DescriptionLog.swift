import Foundation

/// A task description as a list of time-stamped notes, newest first.
///
/// Stored in `descriptionMd`, so sync, search, Obsidian and the AI keep
/// working on plain text. Each note starts with a marker line that Markdown
/// viewers (Obsidian's reading view) hide:
///
///     <!-- note 2026-11-20T16:25:11Z -->
///     Alex followed up about CTASK0012399…
///
/// Text with no marker (older descriptions, a capture summary) is one note
/// dated when the task was created.
public enum DescriptionLog {
    public struct Note: Identifiable, Hashable, Sendable {
        /// Position-independent id: the time plus a counter for equal times.
        public var id: String
        public var date: Date
        public var text: String
        /// True for text written before notes had times.
        public var isUndated: Bool

        public init(id: String, date: Date, text: String, isUndated: Bool = false) {
            self.id = id
            self.date = date
            self.text = text
            self.isUndated = isUndated
        }
    }

    static let markerPattern = #"^<!-- note (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z) -->\s*$"#

    /// The notes in `markdown`, newest first. Undated text uses `createdAt`.
    public static func notes(in markdown: String, createdAt: Date) -> [Note] {
        guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let text = markdown
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var notes: [Note] = []

        let leadingEnd = matches.first?.range.location ?? ns.length
        let leading = ns.substring(to: leadingEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        if !leading.isEmpty {
            notes.append(Note(id: "undated", date: createdAt, text: leading, isUndated: true))
        }
        for (index, match) in matches.enumerated() {
            let stamp = ns.substring(with: match.range(at: 1))
            let bodyStart = match.range.location + match.range.length
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: bodyStart, length: bodyEnd - bodyStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let date = parse(stamp), !body.isEmpty else { continue }
            notes.append(Note(id: stamp, date: date, text: body))
        }
        // Unique ids for notes saved in the same second.
        var seen: [String: Int] = [:]
        for index in notes.indices {
            let count = seen[notes[index].id, default: 0]
            seen[notes[index].id] = count + 1
            if count > 0 { notes[index].id += "#\(count)" }
        }
        return notes.sorted { $0.date > $1.date }
    }

    /// Writes notes back, newest first. Undated text stays first and has no
    /// marker (anything before the first marker is the undated note).
    public static func markdown(for notes: [Note]) -> String {
        (notes.filter(\.isUndated) + notes.filter { !$0.isUndated }.sorted { $0.date > $1.date })
            .compactMap { note -> String? in
                let body = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { return nil }
                return note.isUndated ? body : "<!-- note \(stamp(note.date)) -->\n\(body)"
            }
            .joined(separator: "\n\n")
    }

    /// Adds a note at `date` (to the top).
    public static func adding(_ text: String, at date: Date, to markdown: String, createdAt: Date) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return markdown }
        var notes = notes(in: markdown, createdAt: createdAt)
        notes.append(Note(id: stamp(date), date: date, text: body))
        return self.markdown(for: notes)
    }

    /// Changes one note's text; it keeps its time. Empty text removes it.
    public static func updating(_ id: String, to text: String, in markdown: String, createdAt: Date) -> String {
        var notes = notes(in: markdown, createdAt: createdAt)
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return markdown }
        notes[index].text = text
        return self.markdown(for: notes)
    }

    public static func removing(_ id: String, from markdown: String, createdAt: Date) -> String {
        var notes = notes(in: markdown, createdAt: createdAt)
        notes.removeAll { $0.id == id }
        return self.markdown(for: notes)
    }

    /// The description without note markers, for tooltips and the AI.
    public static func plainText(_ markdown: String) -> String {
        guard markdown.contains("<!-- note "),
              let regex = try? NSRegularExpression(pattern: markerPattern, options: [.anchorsMatchLines])
        else { return markdown }
        return regex.stringByReplacingMatches(
            in: markdown, range: NSRange(markdown.startIndex..., in: markdown), withTemplate: ""
        )
        .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func parse(_ stamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: stamp) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: stamp)
    }
}
