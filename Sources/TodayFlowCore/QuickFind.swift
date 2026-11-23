import Foundation

/// What was typed into Quick Find: words to look for plus filters.
///
///     #tag  @person  /project  due:today|tomorrow|week  overdue  done  open
///
/// Filters combine (all must hold). Quoted text is one phrase.
public struct QuickFindQuery: Hashable, Sendable {
    public enum Due: String, Hashable, Sendable, CaseIterable {
        case today, tomorrow, week, overdue
    }

    public enum State: String, Hashable, Sendable {
        case open, done
    }

    /// Words and phrases as typed.
    public var words: [String] = []
    public var tags: [String] = []
    public var contacts: [String] = []
    public var projects: [String] = []
    public var due: Due?
    public var state: State?

    public init() {}

    public var hasFilters: Bool {
        !tags.isEmpty || !contacts.isEmpty || !projects.isEmpty || due != nil || state != nil
    }

    public var isEmpty: Bool { words.isEmpty && !hasFilters }

    public static func parse(_ text: String) -> QuickFindQuery {
        var query = QuickFindQuery()
        for (token, quoted) in tokenize(text) {
            if quoted {
                query.words.append(token)
                continue
            }
            let lower = token.lowercased()
            if token.hasPrefix("#"), token.count > 1 {
                query.tags.append(String(token.dropFirst()))
            } else if token.hasPrefix("@"), token.count > 1 {
                query.contacts.append(String(token.dropFirst()))
            } else if token.hasPrefix("/"), token.count > 1 {
                query.projects.append(String(token.dropFirst()))
            } else if lower.hasPrefix("project:"), token.count > 8 {
                query.projects.append(String(token.dropFirst(8)))
            } else if lower.hasPrefix("due:"), let due = Due(rawValue: String(lower.dropFirst(4))) {
                query.due = due
            } else if lower == "overdue" {
                query.due = .overdue
            } else if lower == "done" || lower == "is:done" {
                query.state = .done
            } else if lower == "open" || lower == "is:open" {
                query.state = .open
            } else {
                query.words.append(token)
            }
        }
        return query
    }

    private static func tokenize(_ text: String) -> [(String, Bool)] {
        var tokens: [(String, Bool)] = []
        var current = ""
        var inQuotes = false
        func flush() {
            let word = current.trimmingCharacters(in: .whitespaces)
            if !word.isEmpty { tokens.append((word, inQuotes)) }
            current = ""
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
        return tokens
    }
}

/// One Quick Find hit: the task, its project, and why it matched.
public struct QuickFindResult: Hashable, Sendable, Identifiable {
    public var item: WorkItem
    public var projectTitle: String?
    public var projectColor: String?
    /// Where the words were found when it was not the title ("Description").
    public var reason: String?
    /// A few words around the match, for that field.
    public var snippet: String?
    public var isRecent: Bool

    public var id: UUIDv7 { item.id }
}

/// Finds tasks fast: recent ones when nothing is typed, otherwise the best
/// matches first (open before done, title before notes).
public enum QuickFind {
    public static func search(
        _ records: [TaskSearchRecord],
        query: QuickFindQuery,
        recent: [UUIDv7] = [],
        now: Date = .now,
        calendar: Calendar = .current,
        limit: Int = 50
    ) -> [QuickFindResult] {
        let byId = Dictionary(records.map { ($0.item.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        let recentRank = Dictionary(recent.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let terms = query.words.map(TaskSearch.normalize)

        var scored: [(score: Double, result: QuickFindResult)] = []
        for record in records {
            let item = record.item
            guard !item.isDeleted, item.kind == .task || item.kind == .subtask else { continue }
            let project = project(of: item, in: byId)
            guard passes(record, project: project, query: query, now: now, calendar: calendar) else { continue }

            var score = 0.0
            var reason: String?
            var snippet: String?
            if !terms.isEmpty {
                guard let match = match(record, terms: terms, words: query.words) else { continue }
                score += match.score
                reason = match.reason
                snippet = match.snippet
            } else if query.isEmpty {
                // Nothing typed: recent tasks, then what is due now.
                let isUrgent = !item.status.isTerminal && item.endAt < calendar.startOfDay(for: now).addingTimeInterval(86_400)
                guard recentRank[item.id] != nil || isUrgent else { continue }
            }

            if !item.status.isTerminal { score += 1_000 }
            if let rank = recentRank[item.id] { score += 400 - Double(min(rank, 39)) * 10 }
            if !item.status.isTerminal, item.endAt < now { score += 60 }
            if calendar.isDate(item.endAt, inSameDayAs: now) { score += 40 }
            // Newer work slightly ahead of old.
            score += max(0, 30 - now.timeIntervalSince(item.updatedAt) / 86_400)

            scored.append((score, QuickFindResult(
                item: item,
                projectTitle: project?.title,
                projectColor: project?.color,
                reason: reason,
                snippet: snippet,
                isRecent: recentRank[item.id] != nil
            )))
        }
        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.result.item.updatedAt > $1.result.item.updatedAt
            }
            .prefix(query.isEmpty ? 12 : limit)
            .map(\.result)
    }

    // MARK: - Filters

    private static func project(of item: WorkItem, in byId: [UUIDv7: WorkItem]) -> WorkItem? {
        var current = item.parentId.flatMap { byId[$0] }
        var hops = 0
        while let candidate = current, hops < 6 {
            if candidate.kind == .project { return candidate }
            current = candidate.parentId.flatMap { byId[$0] }
            hops += 1
        }
        return nil
    }

    private static func loose(_ text: String) -> String {
        TaskSearch.normalize(text)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func passes(
        _ record: TaskSearchRecord, project: WorkItem?, query: QuickFindQuery, now: Date, calendar: Calendar
    ) -> Bool {
        let item = record.item
        switch query.state {
        case .open?: if item.status.isTerminal { return false }
        case .done?: if !item.status.isTerminal { return false }
        case nil: break
        }
        if !query.tags.isEmpty {
            let tags = item.tags.map(loose)
            for wanted in query.tags.map(loose) where !tags.contains(where: { $0.hasPrefix(wanted) }) {
                return false
            }
        }
        if !query.contacts.isEmpty {
            let names = record.contactNames.map(loose)
            for wanted in query.contacts.map(loose) where !names.contains(where: { $0.contains(wanted) }) {
                return false
            }
        }
        if !query.projects.isEmpty {
            guard let project else { return false }
            let title = loose(project.title)
            for wanted in query.projects.map(loose) where !title.contains(wanted) {
                return false
            }
        }
        if let due = query.due {
            let today = calendar.startOfDay(for: now)
            let day = 86_400.0
            switch due {
            case .overdue:
                if item.status.isTerminal || item.endAt >= now { return false }
            case .today:
                if !calendar.isDate(item.endAt, inSameDayAs: now) { return false }
            case .tomorrow:
                if !calendar.isDate(item.endAt, inSameDayAs: today.addingTimeInterval(day)) { return false }
            case .week:
                if item.endAt < today || item.endAt >= today.addingTimeInterval(7 * day) { return false }
            }
        }
        return true
    }

    // MARK: - Words

    private struct Match {
        var score: Double
        var reason: String?
        var snippet: String?
    }

    private static func match(_ record: TaskSearchRecord, terms: [String], words: [String]) -> Match? {
        let fields = TaskSearch.searchableText(for: record).map { ($0.field, $0.text, TaskSearch.normalize($0.text)) }
        var score = 0.0
        var best: (field: TaskSearchField, text: String)?
        for term in terms {
            let hits = fields.filter { $0.2.contains(term) }
            guard !hits.isEmpty else { return nil }
            if hits.contains(where: { $0.0 == .title }) {
                score += 300
            } else if hits.contains(where: { $0.0 == .tag }) {
                score += 150
            } else {
                score += 60
            }
            if best == nil || (best?.field != .title && hits[0].0 == .title) {
                best = (hits[0].0, hits[0].1)
            }
        }
        let title = TaskSearch.normalize(record.item.title)
        let phrase = terms.joined(separator: " ")
        if title.hasPrefix(phrase) { score += 200 }
        // A ticket number typed exactly ("CHG0012345") goes straight to the
        // task named after it (title starts with the number).
        if terms.count == 1, terms[0].count >= 5, terms[0].contains(where: \.isNumber),
           title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first == Substring(terms[0]) {
            score += 1_500
        }

        guard let best, best.field != .title else { return Match(score: score) }
        return Match(
            score: score,
            reason: best.field.label,
            snippet: snippet(in: best.text, around: words)
        )
    }

    /// About 70 characters of `text` around the first word found.
    public static func snippet(in text: String, around words: [String], radius: Int = 35) -> String {
        let flat = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard let range = words.lazy.compactMap({
            flat.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
        }).first else {
            return String(flat.prefix(radius * 2))
        }
        let start = flat.index(range.lowerBound, offsetBy: -radius, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(range.upperBound, offsetBy: radius, limitedBy: flat.endIndex) ?? flat.endIndex
        var piece = String(flat[start..<end]).trimmingCharacters(in: .whitespaces)
        if start > flat.startIndex { piece = "…" + piece }
        if end < flat.endIndex { piece += "…" }
        return piece
    }
}
