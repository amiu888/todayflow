import Foundation

/// A task that looks related to another, and why.
public struct RelatedSuggestion: Hashable, Sendable, Identifiable {
    public var item: WorkItem
    /// Short, readable reasons ("Same ticket CHG0012345").
    public var reasons: [String]
    public var score: Int
    /// Strong matches are pre-selected when grouping.
    public var isStrong: Bool { score >= 6 }
    public var id: UUIDv7 { item.id }
}

/// Finds tasks that belong with a given task: the same ticket number,
/// email thread, contact, tags, or a very similar title.
public enum RelatedTasks {
    /// Ticket and issue numbers: CHG0012345, CTASK0012399, INC123456, ABC-123.
    public static func tickets(in text: String) -> Set<String> {
        let pattern = #"\b([A-Z]{2,10}\d{4,}|[A-Z][A-Z0-9]{1,9}-\d{1,6})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    /// An email subject without RE:/FW: prefixes, for matching threads.
    public static func threadKey(_ subject: String) -> String {
        var value = subject.trimmingCharacters(in: .whitespaces)
        while let range = value.range(of: #"^(re|fw|fwd|aw|sv)\s*:\s*"#, options: [.regularExpression, .caseInsensitive]) {
            value.removeSubrange(range)
        }
        return value.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private static func tickets(of record: TaskSearchRecord) -> Set<String> {
        let item = record.item
        return tickets(in: [item.title, item.summary, item.descriptionMd, item.tags.joined(separator: " ")]
            .joined(separator: "\n"))
    }

    private static func threads(of record: TaskSearchRecord) -> Set<String> {
        Set(record.attachments.filter { $0.kind == .email }.map { threadKey($0.displayName) }.filter { $0.count > 4 })
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "about", "into", "this", "that", "task", "re", "fw", "to", "of", "on", "in",
    ]

    private static func titleWords(_ title: String) -> Set<String> {
        Set(TaskSearch.normalize(title)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    /// Related tasks, best first. Projects, deleted tasks and the task
    /// itself are left out.
    public static func suggest(
        for target: TaskSearchRecord,
        among records: [TaskSearchRecord],
        limit: Int = 30
    ) -> [RelatedSuggestion] {
        let candidates = records.filter {
            $0.item.id != target.item.id && !$0.item.isDeleted
                && ($0.item.kind == .task || $0.item.kind == .subtask)
        }
        // Tags on most tasks ("work") say nothing about being related.
        var tagUse: [String: Int] = [:]
        for record in candidates { for tag in Set(record.item.tags.map { $0.lowercased() }) { tagUse[tag, default: 0] += 1 } }
        let commonLimit = max(5, candidates.count / 3)

        let targetTickets = tickets(of: target)
        let targetThreads = threads(of: target)
        let targetContacts = Set(target.contactNames)
        let targetTags = Set(target.item.tags.map { $0.lowercased() })
        let targetWords = titleWords(target.item.title)

        var suggestions: [RelatedSuggestion] = []
        for record in candidates {
            var reasons: [String] = []
            var score = 0
            let sharedTickets = targetTickets.intersection(tickets(of: record))
            if let ticket = sharedTickets.sorted().first {
                reasons.append("Same ticket \(ticket)")
                score += 10
            }
            if !targetThreads.intersection(threads(of: record)).isEmpty {
                reasons.append("Same email thread")
                score += 8
            }
            if let contact = targetContacts.intersection(record.contactNames).sorted().first {
                reasons.append("Same contact \(contact)")
                score += 4
            }
            let sharedTags = targetTags.intersection(record.item.tags.map { $0.lowercased() })
                .filter { (tagUse[$0] ?? 0) <= commonLimit }
                // A ticket tag already counted above.
                .filter { tag in !sharedTickets.contains { $0.lowercased() == tag } }
            if !sharedTags.isEmpty {
                let names = record.item.tags.filter { sharedTags.contains($0.lowercased()) }
                reasons.append(names.prefix(2).map { "#\($0)" }.joined(separator: " "))
                score += 3 * min(sharedTags.count, 3)
            }
            let sharedWords = targetWords.intersection(titleWords(record.item.title))
            if sharedWords.count >= 2 {
                reasons.append("Similar title")
                score += 2
            }
            guard score >= 3 else { continue }
            suggestions.append(RelatedSuggestion(item: record.item, reasons: reasons, score: score))
        }
        return suggestions
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.item.status.isTerminal != $1.item.status.isTerminal { return !$0.item.status.isTerminal }
                return $0.item.updatedAt > $1.item.updatedAt
            }
            .prefix(limit)
            .map { $0 }
    }

    /// A name for a new project made from these tasks: their shared ticket
    /// number, else a shared tag, else the first task's title.
    public static func projectName(for target: TaskSearchRecord, with others: [TaskSearchRecord]) -> String {
        let targetTickets = tickets(of: target)
        if let ticket = targetTickets.sorted().first(where: { ticket in
            others.contains { tickets(of: $0).contains(ticket) }
        }) ?? targetTickets.sorted().first {
            return ticket
        }
        let shared = others.reduce(Set(target.item.tags.map { $0.lowercased() })) {
            $0.intersection($1.item.tags.map { $0.lowercased() })
        }
        if let tag = target.item.tags.first(where: { shared.contains($0.lowercased()) }), !others.isEmpty {
            return tag
        }
        return String(target.item.title.prefix(60))
    }
}
