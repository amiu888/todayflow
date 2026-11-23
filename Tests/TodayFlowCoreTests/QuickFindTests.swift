import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Quick Find")
struct QuickFindTests {
    private let now = Date(timeIntervalSince1970: 1_795_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func record(
        _ title: String, note: String = "", tags: [String] = [], contacts: [String] = [],
        status: Status = .todo, dueInDays: Double = 1, parent: UUIDv7? = nil, kind: WorkItem.Kind = .task
    ) -> TaskSearchRecord {
        let due = now.addingTimeInterval(dueInDays * 86_400)
        let item = WorkItem(
            kind: kind, title: title, parentId: parent, descriptionMd: note, status: status,
            startAt: due.addingTimeInterval(-3_600), endAt: due,
            completedAt: status == .done ? now : nil, tags: tags, createdAt: now, updatedAt: now
        )
        return TaskSearchRecord(item: item, contactNames: contacts)
    }

    @Test func parsesFiltersAndWords() {
        let query = QuickFindQuery.parse(#"#billing @Alex /Website due:week overdue done "java client" patch"#)
        #expect(query.tags == ["billing"])
        #expect(query.contacts == ["Alex"])
        #expect(query.projects == ["Website"])
        #expect(query.due == .overdue) // the later due filter wins
        #expect(query.state == .done)
        #expect(query.words == ["java client", "patch"])
    }

    @Test func titleMatchesBeatNoteMatchesAndOpenBeatsDone() {
        let inNote = record("Server work", note: "remove java from the app servers")
        let inTitle = record("Remove java")
        let doneTitle = record("Java upgrade", status: .done)
        let results = QuickFind.search(
            [inNote, doneTitle, inTitle], query: .parse("java"), now: now, calendar: calendar
        )
        #expect(results.map(\.item.title) == ["Remove java", "Server work", "Java upgrade"])
        let noteHit = results[1]
        #expect(noteHit.reason == "Description")
        #expect(noteHit.snippet?.contains("remove java from") == true)
    }

    @Test func aTicketNumberJumpsToItsTask() {
        let mention = record("Patch servers before CHG0012345 window")
        let ticket = record("CHG0012345 - remove Java", status: .done)
        let results = QuickFind.search([mention, ticket], query: .parse("chg0012345"), now: now, calendar: calendar)
        #expect(results.first?.item.title == "CHG0012345 - remove Java")
    }

    @Test func filtersByTagContactProjectAndDue() {
        let project = record("Website", kind: .project)
        let a = record("Hero image", tags: ["design"], contacts: ["Alex Morgan"], dueInDays: 0.1, parent: project.item.id)
        let b = record("Footer", tags: ["design"], dueInDays: 5)
        let late = record("Invoice", dueInDays: -1)
        let all = [project, a, b, late]

        func titles(_ text: String) -> [String] {
            QuickFind.search(all, query: .parse(text), now: now, calendar: calendar).map(\.item.title)
        }
        #expect(Set(titles("#design")) == ["Hero image", "Footer"])
        #expect(titles("#design @alex") == ["Hero image"])
        #expect(titles("/web") == ["Hero image"])
        #expect(titles("due:today") == ["Hero image"])
        #expect(titles("overdue") == ["Invoice"])
        #expect(Set(titles("due:week")) == ["Hero image", "Footer"])
        // Projects themselves are not results.
        #expect(!titles("website").contains("Website"))
    }

    @Test func resultsCarryTheirProject() {
        let project = record("Website", kind: .project)
        let task = record("Hero image", parent: project.item.id)
        let result = QuickFind.search([project, task], query: .parse("hero"), now: now, calendar: calendar).first
        #expect(result?.projectTitle == "Website")
    }

    @Test func emptySearchShowsRecentThenDueNow() {
        let old = record("Old thing", dueInDays: 30)
        let viewed = record("Looked at this", dueInDays: 20)
        let late = record("Late one", dueInDays: -2)
        let results = QuickFind.search(
            [old, viewed, late], query: .parse(""), recent: [viewed.item.id], now: now, calendar: calendar
        )
        #expect(results.map(\.item.title) == ["Looked at this", "Late one"])
        #expect(results.first?.isRecent == true)
    }

    @Test func snippetIsShortAndMarksCuts() {
        let text = String(repeating: "word ", count: 30) + "needle" + String(repeating: " word", count: 30)
        let snippet = QuickFind.snippet(in: text, around: ["needle"])
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.contains("needle"))
        #expect(snippet.count < 90)
    }
}
