import Foundation

/// Optional Obsidian bridge settings. Everything is off by default; an app
/// without Obsidian keeps working normally.
public struct ObsidianSettings: Codable, Hashable, Sendable {
    public static let defaultNotePath = "TodayFlow/Tasks.md"

    public var enabled: Bool
    /// Absolute path to the vault folder on disk.
    public var vaultPath: String
    /// The vault name Obsidian uses in `obsidian://` links (usually the folder name).
    public var vaultName: String
    /// Vault-relative note path used for the two-way task note.
    public var notePath: String

    public init(
        enabled: Bool = false,
        vaultPath: String = "",
        vaultName: String = "",
        notePath: String = ObsidianSettings.defaultNotePath
    ) {
        self.enabled = enabled
        self.vaultPath = vaultPath
        self.vaultName = vaultName
        self.notePath = notePath
    }

    public var isConfigured: Bool {
        enabled
            && !vaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !normalizedNotePath.isEmpty
    }

    public var vaultURL: URL? {
        let path = vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// A safe relative path inside the vault, always ending in `.md`.
    public var normalizedNotePath: String {
        var path = notePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty { path = Self.defaultNotePath }
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        return path
    }

    public var noteURL: URL? {
        guard let vaultURL else { return nil }
        return vaultURL.appendingPathComponent(normalizedNotePath)
    }

    public var resolvedVaultName: String {
        let stored = vaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stored.isEmpty { return stored }
        return vaultURL?.lastPathComponent ?? ""
    }
}

/// Builds Obsidian deep links without pulling AppKit into the core.
public enum ObsidianDeepLink {
    public static func open(vaultName: String, notePath: String) -> URL? {
        var path = notePath.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        if path.lowercased().hasSuffix(".md") { path.removeLast(3) }
        guard !vaultName.isEmpty, !path.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: path),
        ]
        return components.url
    }
}

/// One checklist line parsed from the managed block.
public struct ObsidianParsedLine: Hashable, Sendable {
    public let id: UUIDv7?
    public let title: String
    public let isDone: Bool
    public let tags: [String]
    public let dueAt: Date?
    public let dueHasTime: Bool
    public let isProject: Bool

    public init(
        id: UUIDv7?,
        title: String,
        isDone: Bool,
        tags: [String],
        dueAt: Date?,
        dueHasTime: Bool = false,
        isProject: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.tags = tags
        self.dueAt = dueAt
        self.dueHasTime = dueHasTime
        self.isProject = isProject
    }
}

/// Renders and parses the Markdown block TodayFlow owns. Everything outside
/// the markers is preserved, so the note can live inside a larger Obsidian
/// note without being overwritten.
public enum ObsidianNote {
    public static let startMarker = "<!-- todayflow:start -->"
    public static let endMarker = "<!-- todayflow:end -->"

    public static func render(
        items: [WorkItem],
        projects: [WorkItem],
        existing: String?,
        now: Date = .now,
        calendar: WorkCalendar = .standard
    ) -> String {
        let block = "\(startMarker)\n\(body(items: items, projects: projects, now: now, calendar: calendar))\n\(endMarker)"
        guard let existing, !existing.isEmpty else {
            return block + "\n"
        }
        if let start = existing.range(of: startMarker),
           let end = existing.range(of: endMarker, range: start.upperBound..<existing.endIndex)
        {
            return existing.replacingCharacters(
                in: start.lowerBound..<end.upperBound,
                with: block
            )
        }
        return existing + "\n\n" + block + "\n"
    }

    public static func parse(
        _ note: String,
        calendar: Calendar = .current
    ) -> [ObsidianParsedLine] {
        guard let start = note.range(of: startMarker),
              let end = note.range(of: endMarker, range: start.upperBound..<note.endIndex)
        else { return [] }

        let block = String(note[start.upperBound..<end.lowerBound])
        return block
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0), calendar: calendar) }
    }

    // MARK: Rendering

    private static func body(
        items: [WorkItem],
        projects: [WorkItem],
        now: Date,
        calendar: WorkCalendar
    ) -> String {
        let eob = calendar.endOfBusiness(for: now)
        let dayStart = calendar.calendar.startOfDay(for: now)

        let open = items
            .filter {
                !$0.isDeleted
                    && ($0.kind == .task || $0.kind == .subtask)
                    && !$0.status.isTerminal
            }
            .sorted(by: taskOrder)
        let overdue = open.filter { $0.endAt < now }
        let today = open.filter { $0.endAt >= now && $0.endAt <= eob }
        let upcoming = open.filter { $0.endAt > eob }
        let doneToday = items
            .filter {
                !$0.isDeleted
                    && ($0.kind == .task || $0.kind == .subtask)
                    && $0.status.isComplete
                    && ($0.completedAt ?? .distantPast) >= dayStart
            }
            .sorted(by: taskOrder)

        var lines: [String] = []
        lines.append("# TodayFlow")
        lines.append("")
        lines.append("_Synced \(timestamp(now, calendar: calendar.calendar)). Edit checkboxes, titles, tags, or due dates here._")
        lines.append("_New checklist lines without an ID become tasks. Removing a line does not delete the task._")
        lines.append("")

        appendSection("Overdue", items: overdue, calendar: calendar, to: &lines)
        appendSection("Today", items: today, calendar: calendar, to: &lines)
        appendSection("Upcoming", items: upcoming, calendar: calendar, to: &lines)
        appendSection("Done today", items: doneToday, calendar: calendar, to: &lines)

        let openProjects = projects
            .filter {
                !$0.isDeleted
                    && $0.kind == .project
                    && !$0.status.isTerminal
            }
            .sorted { $0.displayOrder < $1.displayOrder }
        if !openProjects.isEmpty {
            lines.append("## Projects")
            for project in openProjects {
                var line = "- **\(escaped(project.title))** \(idToken(project.id))"
                let tags = tagTokens(project.tags)
                if !tags.isEmpty { line += " \(tags)" }
                lines.append(line)
            }
            lines.append("")
        }

        // Remove the trailing blank line, but keep the block readable.
        if lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    private static func appendSection(
        _ title: String,
        items: [WorkItem],
        calendar: WorkCalendar,
        to lines: inout [String]
    ) {
        guard !items.isEmpty else { return }
        lines.append("## \(title)")
        for item in items {
            let box = item.status.isComplete ? "x" : " "
            var line = "- [\(box)] \(escaped(item.title)) \(idToken(item.id))"
            let tags = tagTokens(item.tags)
            if !tags.isEmpty { line += " \(tags)" }
            line += " \(dueTokens(item.endAt, calendar: calendar.calendar))"
            lines.append(line)
        }
        lines.append("")
    }

    private static func taskOrder(_ lhs: WorkItem, _ rhs: WorkItem) -> Bool {
        if lhs.endAt != rhs.endAt { return lhs.endAt < rhs.endAt }
        return lhs.displayOrder < rhs.displayOrder
    }

    private static func idToken(_ id: UUIDv7) -> String {
        "<!-- todayflow:\(id) -->"
    }

    private static func tagTokens(_ tags: [String]) -> String {
        tags.map { "#\($0.replacingOccurrences(of: " ", with: "-"))" }
            .joined(separator: " ")
    }

    private static func dueTokens(_ date: Date, calendar: Calendar) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm"
        return "📅 \(dateFormatter.string(from: date)) ⏰ \(timeFormatter.string(from: date))"
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Parsing

    private static func parseLine(
        _ line: String,
        calendar: Calendar
    ) -> ObsidianParsedLine? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // A project line is bold and has no checkbox.
        if trimmed.hasPrefix("- **") {
            guard let close = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 4)..<trimmed.endIndex)
            else { return nil }
            let title = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<close.lowerBound])
            let rest = String(trimmed[close.upperBound...])
            return ObsidianParsedLine(
                id: parseID(rest),
                title: cleanTitle(title),
                isDone: false,
                tags: parseTags(rest),
                dueAt: nil,
                dueHasTime: false,
                isProject: true
            )
        }

        guard trimmed.hasPrefix("- ["),
              let close = trimmed.firstIndex(of: "]"),
              trimmed.distance(from: trimmed.startIndex, to: close) == 4
        else { return nil }
        let box = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)]
        guard box == " " || box == "x" || box == "X" else { return nil }

        let rest = String(trimmed[trimmed.index(after: close)...])
            .trimmingCharacters(in: .whitespaces)
        let id = parseID(rest)
        let tagText: String
        if let end = rest.range(of: "-->")?.upperBound {
            tagText = String(rest[end...])
        } else {
            tagText = rest
        }
        return ObsidianParsedLine(
            id: id,
            title: cleanTitle(rest),
            isDone: box == "x" || box == "X",
            tags: parseTags(tagText),
            dueAt: parseDue(rest, calendar: calendar).date,
            dueHasTime: parseDue(rest, calendar: calendar).hasTime
        )
    }

    private static func parseID(_ text: String) -> UUIDv7? {
        guard let range = text.range(
            of: "<!--\\s*todayflow:([0-9A-Fa-f-]{36})\\s*-->",
            options: .regularExpression
        ) else { return nil }
        let marker = String(text[range])
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "todayflow:", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let uuid = UUID(uuidString: marker) else { return nil }
        return UUIDv7(uuid)
    }

    private static func parseTags(_ text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "#([A-Za-z0-9_][A-Za-z0-9_/-]*)"
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func parseDue(
        _ text: String,
        calendar: Calendar
    ) -> (date: Date?, hasTime: Bool) {
        guard let dateRange = text.range(
            of: "📅\\s*\\d{4}-\\d{2}-\\d{2}",
            options: .regularExpression
        ) else { return (nil, false) }
        let dateString = String(text[dateRange])
            .replacingOccurrences(of: "📅", with: "")
            .trimmingCharacters(in: .whitespaces)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard var date = formatter.date(from: dateString) else { return (nil, false) }
        var hasTime = false

        if let timeRange = text.range(
            of: "⏰\\s*\\d{2}:\\d{2}",
            options: .regularExpression
        ) {
            let timeString = String(text[timeRange])
                .replacingOccurrences(of: "⏰", with: "")
                .trimmingCharacters(in: .whitespaces)
            let parts = timeString.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                hasTime = true
                var components = calendar.dateComponents(
                    [.year, .month, .day],
                    from: date
                )
                components.hour = parts[0]
                components.minute = parts[1]
                components.timeZone = calendar.timeZone
                date = calendar.date(from: components) ?? date
            }
        }
        return (date, hasTime)
    }

    private static func cleanTitle(_ text: String) -> String {
        var result = text
        for pattern in [
            "<!--\\s*todayflow:[^>]+\\s*-->",
            "📅\\s*\\d{4}-\\d{2}-\\d{2}",
            "⏰\\s*\\d{2}:\\d{2}",
            "#[A-Za-z0-9_][A-Za-z0-9_/-]*",
        ] {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A note generated for one task or project. Unlike the central sync note,
/// this is a one-way snapshot that is safe to regenerate whenever the user
/// clicks "Open in Obsidian".
public enum ObsidianItemNote {
    public static func render(
        item: WorkItem,
        projectTitle: String? = nil,
        now: Date = .now
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")!
        let kind = item.kind.rawValue
        let due = formatter.string(from: item.endAt)
        let tags = item.tags.isEmpty
            ? "[]"
            : "\n" + item.tags.map { "  - \($0)" }.joined(separator: "\n")
        let project = projectTitle.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" } ?? ""

        var body = """
        ---
        todayflow_id: \(item.id)
        kind: \(kind)
        status: \(item.status.rawValue)
        priority: \(item.priority.rawValue)
        due: \(due)
        tags: \(tags)
        project: \(project)
        ---

        # \(item.title)

        """
        if !item.descriptionMd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += item.descriptionMd + "\n\n"
        }
        body += "_Task note from TodayFlow. The central TodayFlow sync note is the two-way one._\n"
        return body
    }
}

/// A vault registered with the Obsidian desktop app.
public struct ObsidianVault: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

/// Parses Obsidian's `obsidian.json` vault registry so Settings can offer the
/// same vaults the user sees in Obsidian's switcher.
public enum ObsidianVaultRegistry {
    private struct Registry: Decodable {
        struct Entry: Decodable {
            let path: String
        }
        let vaults: [String: Entry]
    }

    public static func parse(_ json: String) -> [ObsidianVault] {
        guard let data = json.data(using: .utf8),
              let registry = try? JSONDecoder().decode(Registry.self, from: data)
        else { return [] }

        var seen = Set<String>()
        let vaults = registry.vaults.values
            .map { entry in
                let url = URL(fileURLWithPath: entry.path)
                return ObsidianVault(
                    name: url.lastPathComponent,
                    path: entry.path
                )
            }
            .filter { seen.insert($0.path).inserted }
        let paths = Set(vaults.map(\.path))
        return vaults
            .filter { vault in
                // A parent folder registered as a vault is shown by Obsidian
                // as a container for its nested vaults; don't duplicate it in
                // the picker when a child vault is present.
                !paths.contains { other in
                    other != vault.path && other.hasPrefix(vault.path + "/")
                }
            }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
