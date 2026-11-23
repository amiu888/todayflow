import Foundation

/// "What I did today" for management: short, grouped, and checkable (each
/// line keeps the task title, so ticket numbers stay visible).
public struct DailyReport: Hashable, Sendable {
    public struct Line: Hashable, Sendable, Identifiable {
        public var id: UUIDv7
        public var title: String
        public var project: String?
        public var priority: Priority
        public var status: Status
        public var dueAt: Date
        public var completedAt: Date?
        /// The latest note written that day (first lines, trimmed).
        public var note: String?
        public var estimatedMinutes: Int?

        public init(
            id: UUIDv7, title: String, project: String? = nil, priority: Priority,
            status: Status, dueAt: Date, completedAt: Date? = nil, note: String? = nil,
            estimatedMinutes: Int? = nil
        ) {
            self.id = id
            self.title = title
            self.project = project
            self.priority = priority
            self.status = status
            self.dueAt = dueAt
            self.completedAt = completedAt
            self.note = note
            self.estimatedMinutes = estimatedMinutes
        }
    }

    public var day: Date
    /// Finished that day.
    public var completed: [Line] = []
    /// Worked on that day (a note or "In progress") and still open.
    public var inProgress: [Line] = []
    /// Blocked tasks: need management's attention.
    public var blocked: [Line] = []
    /// Due that day (or earlier) with no work recorded; carried forward.
    public var carriedOver: [Line] = []
    /// Due on the next working day.
    public var nextUp: [Line] = []

    public init(day: Date) {
        self.day = day
    }

    public var isEmpty: Bool {
        completed.isEmpty && inProgress.isEmpty && blocked.isEmpty && carriedOver.isEmpty && nextUp.isEmpty
    }

    /// Estimated minutes of the completed work, when any task has an estimate.
    public var completedMinutes: Int? {
        let values = completed.compactMap(\.estimatedMinutes)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}

public extension DailyReport {
    /// Which parts go into the text.
    struct Options: Hashable, Sendable {
        public var includeNotes: Bool
        public var includePriority: Bool
        public var includeNextUp: Bool
        public var markdown: Bool
        /// Shown under the heading, e.g. the person's name.
        public var author: String

        public init(
            includeNotes: Bool = true, includePriority: Bool = true,
            includeNextUp: Bool = true, markdown: Bool = false, author: String = ""
        ) {
            self.includeNotes = includeNotes
            self.includePriority = includePriority
            self.includeNextUp = includeNextUp
            self.markdown = markdown
            self.author = author
        }
    }

    /// The subject for an email, e.g. "Daily report – Mon 23 Nov 2026".
    func subject(calendar: Calendar = .current) -> String {
        "Daily report – \(Self.dayFormat(day, calendar: calendar))"
    }

    /// One line: "5 completed · 2 in progress · 1 blocked · 1 carried over".
    var headline: String {
        var parts = ["\(completed.count) completed"]
        if !inProgress.isEmpty { parts.append("\(inProgress.count) in progress") }
        if !blocked.isEmpty { parts.append("\(blocked.count) blocked") }
        if !carriedOver.isEmpty { parts.append("\(carriedOver.count) carried over") }
        return parts.joined(separator: " · ")
    }

    /// The report as plain text (for email or chat) or Markdown.
    func text(_ options: Options = Options(), now: Date = .now, calendar: Calendar = .current) -> String {
        let md = options.markdown
        var out: [String] = []
        out.append(md ? "## \(subject(calendar: calendar))" : subject(calendar: calendar))
        if !options.author.trimmingCharacters(in: .whitespaces).isEmpty {
            out.append(options.author.trimmingCharacters(in: .whitespaces))
        }
        var summary = headline
        if let minutes = completedMinutes, minutes > 0 {
            summary += " · about \(Self.hours(minutes)) of planned work done"
        }
        out.append(md ? "**Summary:** \(summary)" : "Summary: \(summary)")

        func section(_ title: String, _ lines: [Line], detail: (Line) -> String?) {
            guard !lines.isEmpty else { return }
            out.append("")
            out.append(md ? "### \(title)" : "\(title.uppercased())")
            for line in lines {
                var text = (md ? "- " : "• ") + line.title
                var tags: [String] = []
                if options.includePriority { tags.append(line.priority.shortLabel) }
                if let project = line.project { tags.append(project) }
                if !tags.isEmpty { text += " (\(tags.joined(separator: ", ")))" }
                if let detail = detail(line) { text += " — \(detail)" }
                out.append(text)
                if options.includeNotes, let note = line.note {
                    out.append("  " + (md ? "_\(note)_" : note))
                }
            }
        }

        section("Completed", completed) { line in
            line.completedAt.map { "done \($0.formatted(date: .omitted, time: .shortened))" }
        }
        section("In progress", inProgress) { line in
            Self.dueText(line.dueAt, now: now, calendar: calendar)
        }
        section("Blocked – needs attention", blocked) { line in
            Self.dueText(line.dueAt, now: now, calendar: calendar)
        }
        section("Not started – carried over", carriedOver) { line in
            Self.dueText(line.dueAt, now: now, calendar: calendar)
        }
        if options.includeNextUp {
            section("Planned next", nextUp) { _ in nil }
        }
        if isEmpty {
            out.append("")
            out.append("No task activity recorded.")
        }
        return out.joined(separator: "\n")
    }

    static func dueText(_ due: Date, now: Date, calendar: Calendar) -> String {
        if due < now {
            return calendar.isDate(due, inSameDayAs: now)
                ? "was due \(due.formatted(date: .omitted, time: .shortened))"
                : "overdue since \(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        }
        if calendar.isDate(due, inSameDayAs: now) {
            return "due \(due.formatted(date: .omitted, time: .shortened))"
        }
        return "due \(due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    static func dayFormat(_ day: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    static func hours(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        let rounded = (hours * 2).rounded() / 2
        return rounded == rounded.rounded() ? "\(Int(rounded)) h" : String(format: "%.1f h", rounded)
    }
}

public enum DailyReportBuilder {
    /// Sorts `items` into the report for `day`. Each task appears once;
    /// epics and projects show only as the project name of their tasks.
    public static func build(
        items: [WorkItem], day: Date, now: Date = .now, calendar: WorkCalendar = .standard
    ) -> DailyReport {
        let cal = calendar.calendar
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let isToday = cal.isDate(day, inSameDayAs: now)
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var report = DailyReport(day: dayStart)

        func project(of item: WorkItem) -> String? {
            var parentId = item.parentId
            var hops = 0
            while let id = parentId, let parent = byId[id], hops < 4 {
                if parent.kind == .project || parent.kind == .epic { return parent.title }
                parentId = parent.parentId
                hops += 1
            }
            return nil
        }

        func noteOfTheDay(_ item: WorkItem) -> String? {
            let notes = DescriptionLog.notes(in: item.descriptionMd, createdAt: item.createdAt)
                .filter { !$0.isUndated && $0.date >= dayStart && $0.date < dayEnd }
            guard let latest = notes.max(by: { $0.date < $1.date }) else { return nil }
            return shorten(DescriptionLog.plainText(latest.text))
        }

        func line(_ item: WorkItem, note: String?) -> DailyReport.Line {
            DailyReport.Line(
                id: item.id, title: item.title, project: project(of: item), priority: item.priority,
                status: item.status, dueAt: item.endAt, completedAt: item.completedAt, note: note,
                estimatedMinutes: item.estimatedMinutes
            )
        }

        // The next working day after `day`.
        var next = dayEnd
        for _ in 0..<7 where !calendar.isWorkingDay(next) {
            next = cal.date(byAdding: .day, value: 1, to: next) ?? next
        }
        let nextEnd = cal.date(byAdding: .day, value: 1, to: next) ?? next

        for item in items where !item.isDeleted && (item.kind == .task || item.kind == .subtask) {
            let note = noteOfTheDay(item)
            if item.status == .done {
                let when = item.completedAt ?? item.updatedAt
                if when >= dayStart && when < dayEnd { report.completed.append(line(item, note: note)) }
                continue
            }
            if item.status == .cancelled { continue }
            // Only the day's own work for a past day; open work as of now for today.
            if item.status == .blocked, item.startAt < dayEnd {
                report.blocked.append(line(item, note: note))
            } else if note != nil || (isToday && item.status == .inProgress) {
                report.inProgress.append(line(item, note: note))
            } else if item.endAt < dayEnd, item.startAt < dayEnd, item.createdAt < dayEnd {
                report.carriedOver.append(line(item, note: nil))
            } else if item.endAt >= next, item.endAt < nextEnd {
                report.nextUp.append(line(item, note: nil))
            }
        }

        report.completed.sort { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
        let byPriority: (DailyReport.Line, DailyReport.Line) -> Bool = {
            $0.priority != $1.priority ? $0.priority < $1.priority : $0.dueAt < $1.dueAt
        }
        report.inProgress.sort(by: byPriority)
        report.blocked.sort(by: byPriority)
        report.carriedOver.sort(by: byPriority)
        report.nextUp.sort(by: byPriority)
        return report
    }

    /// The first two lines of a note, at most 160 characters.
    static func shorten(_ text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        var joined = lines.prefix(2).joined(separator: " ")
        if joined.count > 160 {
            joined = String(joined.prefix(157)).trimmingCharacters(in: .whitespaces) + "…"
        } else if lines.count > 2 {
            joined += " …"
        }
        return joined
    }
}
