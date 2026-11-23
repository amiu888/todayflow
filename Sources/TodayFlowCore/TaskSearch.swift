import Foundation

/// Everything searchable about one task: the item plus the text that lives in
/// related tables (attachments, checklist steps, linked contacts).
public struct TaskSearchRecord: Sendable, Hashable {
    public var item: WorkItem
    public var attachments: [Attachment]
    public var actions: [ActionItem]
    public var contactNames: [String]

    public init(
        item: WorkItem,
        attachments: [Attachment] = [],
        actions: [ActionItem] = [],
        contactNames: [String] = []
    ) {
        self.item = item
        self.attachments = attachments
        self.actions = actions
        self.contactNames = contactNames
    }
}

/// Where a search term was found, so the results list can say why a task matched.
public enum TaskSearchField: String, Sendable, Hashable, CaseIterable, Comparable {
    case title
    case description
    case summary
    case tag
    case attachmentName
    case fileName
    case link
    case attachmentNote
    case attachmentText
    case checklist
    case contact

    public var label: String {
        switch self {
        case .title: "Title"
        case .description: "Description"
        case .summary: "Summary"
        case .tag: "Tag"
        case .attachmentName: "Attachment"
        case .fileName: "File name"
        case .link: "Link"
        case .attachmentNote: "Attachment note"
        case .attachmentText: "Attachment text"
        case .checklist: "Checklist"
        case .contact: "Contact"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order = Self.allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Which tasks to include by status.
public enum TaskSearchScope: String, Sendable, Hashable, CaseIterable {
    case all
    case open
    case done

    public var label: String {
        switch self {
        case .all: "All"
        case .open: "Open"
        case .done: "Closed"
        }
    }
}

/// How results are ordered. `.tag` groups results under each tag.
public enum TaskSearchSort: String, Sendable, Hashable, CaseIterable {
    case newest
    case oldest
    case priority
    case title
    case tag

    public var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .priority: "Priority"
        case .title: "Title"
        case .tag: "Tag"
        }
    }
}

public struct TaskSearchQuery: Sendable, Hashable {
    /// Free text. Words must all match (in any field); `"quoted phrases"`
    /// match as a whole; `#tag` words become tag filters.
    public var text: String
    /// Tags the task must have (all of them), compared case-insensitively.
    public var tags: Set<String>
    /// Inclusive date range the task's start…due (or completion) must overlap.
    public var dateRange: ClosedRange<Date>?
    public var scope: TaskSearchScope
    /// Projects are containers; they are left out unless asked for.
    public var includeProjects: Bool

    public init(
        text: String = "",
        tags: Set<String> = [],
        dateRange: ClosedRange<Date>? = nil,
        scope: TaskSearchScope = .all,
        includeProjects: Bool = false
    ) {
        self.text = text
        self.tags = tags
        self.dateRange = dateRange
        self.scope = scope
        self.includeProjects = includeProjects
    }
}

public struct TaskSearchResult: Sendable, Hashable, Identifiable {
    public var record: TaskSearchRecord
    /// Fields the text matched in, in display order. Empty when no text was given.
    public var matchedFields: [TaskSearchField]

    public var id: UUIDv7 { record.item.id }
    public var item: WorkItem { record.item }
}

public struct TaskSearchGroup: Sendable, Hashable, Identifiable {
    /// The tag for `.tag` sorting, or `nil` for the single ungrouped list and
    /// for the "No tag" group.
    public var tag: String?
    public var title: String
    public var results: [TaskSearchResult]

    public var id: String { tag.map { "tag:\($0.lowercased())" } ?? "ungrouped:\(title)" }
}

/// Searches every task, past and future (not only the Today list).
public enum TaskSearch {
    public struct ParsedText: Sendable, Hashable {
        public var terms: [String]
        public var tags: [String]
    }

    /// Splits search text into normalized terms and `#tag` filters.
    public static func parse(_ text: String) -> ParsedText {
        var terms: [String] = []
        var tags: [String] = []
        var current = ""
        var inQuotes = false

        func flush() {
            let word = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            guard !word.isEmpty else { return }
            if !inQuotes, word.hasPrefix("#"), word.count > 1 {
                tags.append(String(word.dropFirst()))
            } else {
                terms.append(normalize(word))
            }
        }

        for character in text {
            if character == "\"" {
                flush()
                inQuotes.toggle()
            } else if character.isWhitespace, !inQuotes {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return ParsedText(terms: terms, tags: tags)
    }

    /// Case- and accent-insensitive form used on both sides of a comparison.
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Every tag in use, sorted case-insensitively, de-duplicated.
    public static func allTags(in records: [TaskSearchRecord]) -> [String] {
        var byKey: [String: String] = [:]
        for record in records {
            for tag in record.item.tags where byKey[tag.lowercased()] == nil {
                byKey[tag.lowercased()] = tag
            }
        }
        return byKey.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Filters and sorts. Returns one group, or one group per tag for `.tag`.
    public static func run(
        _ records: [TaskSearchRecord],
        query: TaskSearchQuery,
        sort: TaskSearchSort
    ) -> [TaskSearchGroup] {
        let parsed = parse(query.text)
        let requiredTags = Set((Array(query.tags) + parsed.tags).map { $0.lowercased() })

        var results: [TaskSearchResult] = []
        for record in records {
            let item = record.item
            guard !item.isDeleted else { continue }
            if !query.includeProjects, item.kind == .project { continue }
            switch query.scope {
            case .all: break
            case .open: if item.status.isTerminal { continue }
            case .done: if !item.status.isTerminal { continue }
            }
            if !requiredTags.isEmpty {
                let itemTags = Set(item.tags.map { $0.lowercased() })
                guard requiredTags.isSubset(of: itemTags) else { continue }
            }
            if let range = query.dateRange, !overlaps(item, range) { continue }

            if parsed.terms.isEmpty {
                results.append(TaskSearchResult(record: record, matchedFields: []))
                continue
            }
            let fields = haystack(for: record)
            var matched = Set<TaskSearchField>()
            var allFound = true
            for term in parsed.terms {
                let hits = fields.filter { $0.text.contains(term) }.map(\.field)
                if hits.isEmpty {
                    allFound = false
                    break
                }
                matched.formUnion(hits)
            }
            guard allFound else { continue }
            results.append(TaskSearchResult(record: record, matchedFields: matched.sorted()))
        }

        switch sort {
        case .tag:
            return groupByTag(results)
        default:
            return [TaskSearchGroup(tag: nil, title: "Tasks", results: sorted(results, by: sort))]
        }
    }

    // MARK: - Helpers

    /// The date a task is "about": completion for finished tasks, else due.
    public static func referenceDate(for item: WorkItem) -> Date {
        if item.status.isTerminal, let completed = item.completedAt { return completed }
        return item.endAt
    }

    private static func overlaps(_ item: WorkItem, _ range: ClosedRange<Date>) -> Bool {
        let lower = min(item.startAt, item.endAt)
        var upper = max(item.startAt, item.endAt)
        if let completed = item.completedAt { upper = max(upper, completed) }
        return lower <= range.upperBound && upper >= range.lowerBound
    }

    private struct Field {
        var field: TaskSearchField
        var text: String
    }

    private static func haystack(for record: TaskSearchRecord) -> [Field] {
        searchableText(for: record).map { Field(field: $0.field, text: normalize($0.text)) }
    }

    /// Every searchable piece of text about a task, as written, in field
    /// order (title first). Quick Find quotes these to show why a task matched.
    public static func searchableText(for record: TaskSearchRecord) -> [(field: TaskSearchField, text: String)] {
        var fields: [(field: TaskSearchField, text: String)] = []
        func add(_ field: TaskSearchField, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            fields.append((field, value))
        }

        let item = record.item
        add(.title, item.title)
        add(.description, DescriptionLog.plainText(item.descriptionMd))
        add(.summary, item.summary)
        for tag in item.tags { add(.tag, tag) }

        for attachment in record.attachments {
            add(.attachmentName, attachment.displayName)
            add(.attachmentNote, attachment.note)
            add(.attachmentText, attachment.previewText)
            for value in attachment.metadata.values { add(.attachmentText, value) }
            for path in [attachment.reference, attachment.localCopyPath].compactMap({ $0 }) {
                if let url = URL(string: path), let scheme = url.scheme,
                   scheme == "http" || scheme == "https" {
                    add(.link, path)
                    add(.link, url.host)
                } else {
                    add(.fileName, (path as NSString).lastPathComponent)
                    add(.fileName, path)
                }
            }
        }
        for action in record.actions { add(.checklist, action.text) }
        for name in record.contactNames { add(.contact, name) }
        return fields
    }

    private static func sorted(
        _ results: [TaskSearchResult],
        by sort: TaskSearchSort
    ) -> [TaskSearchResult] {
        results.sorted { lhs, rhs in
            let left = lhs.item
            let right = rhs.item
            switch sort {
            case .oldest:
                let (a, b) = (referenceDate(for: left), referenceDate(for: right))
                if a != b { return a < b }
            case .priority:
                if left.priority != right.priority { return left.priority < right.priority }
                let (a, b) = (referenceDate(for: left), referenceDate(for: right))
                if a != b { return a > b }
            case .title:
                let order = left.title.localizedCaseInsensitiveCompare(right.title)
                if order != .orderedSame { return order == .orderedAscending }
            case .newest, .tag:
                let (a, b) = (referenceDate(for: left), referenceDate(for: right))
                if a != b { return a > b }
            }
            return left.id.uuid.uuidString < right.id.uuid.uuidString
        }
    }

    /// One section per tag (a task with two tags appears under both), then
    /// a final "No tag" section.
    private static func groupByTag(_ results: [TaskSearchResult]) -> [TaskSearchGroup] {
        var byKey: [String: (name: String, results: [TaskSearchResult])] = [:]
        var untagged: [TaskSearchResult] = []
        for result in results {
            if result.item.tags.isEmpty {
                untagged.append(result)
                continue
            }
            for tag in result.item.tags {
                let key = tag.lowercased()
                byKey[key, default: (tag, [])].results.append(result)
            }
        }
        var groups = byKey.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map {
                TaskSearchGroup(
                    tag: $0.name,
                    title: "#\($0.name)",
                    results: sorted($0.results, by: .newest)
                )
            }
        if !untagged.isEmpty {
            groups.append(
                TaskSearchGroup(tag: nil, title: "No tag", results: sorted(untagged, by: .newest))
            )
        }
        return groups
    }
}
