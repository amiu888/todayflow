import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Daily report")
struct DailyReportTests {
    // Monday 5 Jan 2026, 16:00 UTC.
    private let now = TestDates.date(2026, 1, 5, hour: 16)
    private let day = TestDates.monday
    private var cal: WorkCalendar { TestDates.workCalendar }

    private func task(
        _ title: String, status: Status = .todo, priority: Priority = .normal,
        due: Date? = nil, completedAt: Date? = nil, note: (String, Date)? = nil,
        parent: UUIDv7? = nil, kind: WorkItem.Kind = .task, minutes: Int? = nil,
        created: Date? = nil
    ) -> WorkItem {
        let created = created ?? TestDates.date(2026, 1, 2, hour: 9)
        var md = ""
        if let note { md = DescriptionLog.adding(note.0, at: note.1, to: "", createdAt: created) }
        let end = due ?? TestDates.date(2026, 1, 5, hour: 17)
        return WorkItem(
            kind: kind, title: title, parentId: parent, descriptionMd: md, status: status, priority: priority,
            startAt: created, endAt: end, estimatedMinutes: minutes, completedAt: completedAt,
            createdAt: created, updatedAt: completedAt ?? created
        )
    }

    @Test func sortsEachTaskIntoOneSection() {
        let project = task("Java removal", kind: .project)
        let items = [
            project,
            task("CHG0012345 - remove Java", status: .done, priority: .urgent,
                 completedAt: TestDates.date(2026, 1, 5, hour: 11), parent: project.id, minutes: 90),
            task("Done last week", status: .done, completedAt: TestDates.date(2026, 1, 2, hour: 11)),
            task("Patch db-server-01", status: .inProgress, priority: .high,
                 due: TestDates.date(2026, 1, 7, hour: 17)),
            task("Reply to Alex", due: TestDates.date(2026, 1, 8, hour: 17),
                 note: ("Sent the draft, waiting on numbers.", TestDates.date(2026, 1, 5, hour: 14))),
            task("Vendor licence", status: .blocked, priority: .high),
            task("Update runbook", due: TestDates.date(2026, 1, 5, hour: 12)),
            task("Plan Q2 review", due: TestDates.date(2026, 1, 6, hour: 17)),
            task("Far future", due: TestDates.date(2026, 2, 6, hour: 17)),
            task("Cancelled", status: .cancelled),
        ]
        let report = DailyReportBuilder.build(items: items, day: day, now: now, calendar: cal)
        #expect(report.completed.map(\.title) == ["CHG0012345 - remove Java"])
        #expect(report.completed.first?.project == "Java removal")
        #expect(report.inProgress.map(\.title) == ["Patch db-server-01", "Reply to Alex"])
        #expect(report.inProgress.last?.note == "Sent the draft, waiting on numbers.")
        #expect(report.blocked.map(\.title) == ["Vendor licence"])
        #expect(report.carriedOver.map(\.title) == ["Update runbook"])
        #expect(report.nextUp.map(\.title) == ["Plan Q2 review"])
        #expect(report.completedMinutes == 90)
    }

    @Test func nextUpSkipsTheWeekend() {
        let friday = TestDates.friday
        let monday = TestDates.date(2026, 1, 12, hour: 17)
        let items = [task("Monday work", due: monday, created: TestDates.date(2026, 1, 9, hour: 9))]
        let report = DailyReportBuilder.build(items: items, day: friday, now: TestDates.date(2026, 1, 9, hour: 16), calendar: cal)
        #expect(report.nextUp.map(\.title) == ["Monday work"])
    }

    @Test func pastDayIgnoresInProgressWithoutWorkThatDay() {
        let items = [task("Long running", status: .inProgress, due: TestDates.date(2026, 1, 20, hour: 17))]
        let report = DailyReportBuilder.build(items: items, day: TestDates.date(2026, 1, 2), now: now, calendar: cal)
        #expect(report.inProgress.isEmpty)
    }

    @Test func textHasHeadlineSectionsAndOptions() {
        let items = [
            task("CHG0012345 - remove Java", status: .done, priority: .urgent,
                 completedAt: TestDates.date(2026, 1, 5, hour: 11),
                 note: ("Closed after checks.", TestDates.date(2026, 1, 5, hour: 11))),
            task("Vendor licence", status: .blocked, priority: .high),
        ]
        let report = DailyReportBuilder.build(items: items, day: day, now: now, calendar: cal)
        let text = report.text(.init(author: "Alex, Infrastructure"), now: now, calendar: TestDates.calendar)
        #expect(text.hasPrefix("Daily report – Mon, 5 Jan 2026") || text.hasPrefix("Daily report – Mon, Jan 5, 2026"))
        #expect(text.contains("Alex, Infrastructure"))
        #expect(text.contains("Summary: 1 completed · 1 blocked"))
        #expect(text.contains("COMPLETED\n• CHG0012345 - remove Java (P1) — done"))
        #expect(text.contains("  Closed after checks."))
        #expect(text.contains("BLOCKED – NEEDS ATTENTION\n• Vendor licence (P2)"))

        let bare = report.text(.init(includeNotes: false, includePriority: false, markdown: true), now: now, calendar: TestDates.calendar)
        #expect(bare.contains("### Completed\n- CHG0012345 - remove Java — done"))
        #expect(!bare.contains("Closed after checks."))
        #expect(!bare.contains("(P1)"))
    }

    @Test func emptyDaySaysSo() {
        let report = DailyReportBuilder.build(items: [], day: day, now: now, calendar: cal)
        #expect(report.text(now: now).contains("No task activity recorded."))
    }

    @Test func longNotesAreShortened() {
        let long = String(repeating: "word ", count: 60)
        #expect(DailyReportBuilder.shorten(long)!.count <= 158)
        #expect(DailyReportBuilder.shorten("a\nb\nc") == "a b …")
    }
}
