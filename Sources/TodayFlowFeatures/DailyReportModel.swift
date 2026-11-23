import Foundation
import Observation
import TodayFlowCore

/// The Daily Report window: builds the report for a day, keeps the text the
/// person edits, and hands it to Copy / Email / Save.
@MainActor
@Observable
public final class DailyReportModel {
    static let optionsKey = "todayflow.dailyReport."

    public private(set) var report: DailyReport
    public var day: Date {
        didSet { if !calendar.calendar.isDate(day, inSameDayAs: oldValue) { Task { await load() } } }
    }
    public var includeNotes: Bool { didSet { optionChanged("notes", includeNotes) } }
    public var includePriority: Bool { didSet { optionChanged("priority", includePriority) } }
    public var includeNextUp: Bool { didSet { optionChanged("next", includeNextUp) } }
    public var markdown: Bool { didSet { optionChanged("markdown", markdown) } }
    public var author: String {
        didSet {
            defaults.set(author, forKey: Self.optionsKey + "author")
            regenerate()
        }
    }
    /// The report text; the person may edit it before sending.
    public var text: String = ""
    /// True once the text differs from what the app generated.
    public var isEdited: Bool { text != generated }
    public private(set) var isLoading = false
    public private(set) var copied = false

    @ObservationIgnored private var generated = ""
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let defaults: UserDefaults

    @ObservationIgnored public var onCopy: (@MainActor (String) -> Void)?
    @ObservationIgnored public var onEmail: (@MainActor (_ subject: String, _ body: String) -> Void)?
    @ObservationIgnored public var onSave: (@MainActor (_ suggestedName: String, _ text: String) -> Void)?
    @ObservationIgnored public var onOpenTask: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        clock: @escaping @Sendable () -> Date = { .now },
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.calendar = calendar
        self.clock = clock
        self.defaults = defaults
        let today = calendar.calendar.startOfDay(for: clock())
        self.day = today
        self.report = DailyReport(day: today)
        func flag(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: Self.optionsKey + name) as? Bool ?? fallback
        }
        includeNotes = flag("notes", true)
        includePriority = flag("priority", true)
        includeNextUp = flag("next", true)
        markdown = flag("markdown", false)
        author = defaults.string(forKey: Self.optionsKey + "author") ?? ""
    }

    public var isToday: Bool { calendar.calendar.isDate(day, inSameDayAs: clock()) }

    public var options: DailyReport.Options {
        DailyReport.Options(
            includeNotes: includeNotes, includePriority: includePriority,
            includeNextUp: includeNextUp, markdown: markdown, author: author
        )
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let items = await repository.allItems()
        report = DailyReportBuilder.build(items: items, day: day, now: clock(), calendar: calendar)
        regenerate(force: true)
    }

    /// Rebuilds the text from the report. Keeps the person's edits unless
    /// `force` (a new day or "Start Over").
    public func regenerate(force: Bool = false) {
        let wasEdited = isEdited && !generated.isEmpty
        generated = report.text(options, now: clock(), calendar: calendar.calendar)
        if force || !wasEdited { text = generated }
    }

    /// Discards edits and rebuilds.
    public func startOver() {
        regenerate(force: true)
    }

    public func previousDay() { step(-1) }
    public func nextDay() { if !isToday { step(1) } }
    public func goToToday() { day = calendar.calendar.startOfDay(for: clock()) }

    private func step(_ days: Int) {
        if let date = calendar.calendar.date(byAdding: .day, value: days, to: day) { day = date }
    }

    public func copy() {
        onCopy?(text)
        copied = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.copied = false
        }
    }

    public func email() {
        onEmail?(report.subject(calendar: calendar.calendar), text)
    }

    public func save() {
        let formatter = DateFormatter()
        formatter.calendar = calendar.calendar
        formatter.dateFormat = "yyyy-MM-dd"
        onSave?("Daily report \(formatter.string(from: day)).\(markdown ? "md" : "txt")", text)
    }

    private func optionChanged(_ name: String, _ value: Bool) {
        defaults.set(value, forKey: Self.optionsKey + name)
        regenerate()
    }
}
