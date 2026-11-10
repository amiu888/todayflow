import Foundation
import Testing
import TodayFlowCore

private func task(
    _ title: String,
    description: String = "",
    tags: [String] = [],
    status: Status = .todo,
    priority: Priority = .default,
    start: Date = TestDates.monday,
    due: Date = TestDates.monday,
    completed: Date? = nil,
    kind: WorkItem.Kind = .task
) -> WorkItem {
    WorkItem(
        kind: kind,
        title: title,
        descriptionMd: description,
        status: status,
        priority: priority,
        startAt: start,
        endAt: due,
        completedAt: completed,
        tags: tags
    )
}

private func titles(_ groups: [TaskSearchGroup]) -> [String] {
    groups.flatMap { $0.results.map(\.item.title) }
}

@Test func parseSplitsWordsQuotedPhrasesAndHashTags() {
    let parsed = TaskSearch.parse(#"Invoice "Q3 report" #work  #Urgent"#)
    #expect(parsed.terms == ["invoice", "q3 report"])
    #expect(parsed.tags == ["work", "Urgent"])
}

@Test func searchMatchesTitleDescriptionAndIsAccentInsensitive() {
    let records = [
        TaskSearchRecord(item: task("Café menu")),
        TaskSearchRecord(item: task("Other", description: "call the CAFE owner")),
        TaskSearchRecord(item: task("Unrelated")),
    ]
    let groups = TaskSearch.run(records, query: TaskSearchQuery(text: "cafe"), sort: .title)
    #expect(titles(groups) == ["Café menu", "Other"])
    #expect(groups[0].results[0].matchedFields == [.title])
    #expect(groups[0].results[1].matchedFields == [.description])
}

@Test func searchFindsAttachmentNamesFileNamesLinksNotesChecklistAndContacts() {
    let item = task("Plain title")
    let records = [
        TaskSearchRecord(
            item: item,
            attachments: [
                Attachment(itemId: item.id, kind: .file, displayName: "Budget",
                           reference: "/Users/me/Docs/budget-2026.xlsx"),
                Attachment(itemId: item.id, kind: .url, displayName: "Spec page",
                           reference: "https://wiki.example.com/spec", note: "read before standup"),
            ],
            actions: [ActionItem(itemId: item.id, text: "Email Dana")],
            contactNames: ["Priya Natarajan"]
        ),
    ]
    func found(_ text: String) -> [TaskSearchField] {
        TaskSearch.run(records, query: TaskSearchQuery(text: text), sort: .newest)
            .first?.results.first?.matchedFields ?? []
    }
    #expect(found("budget-2026.xlsx") == [.fileName])
    #expect(found("\"spec page\"") == [.attachmentName])
    #expect(found("spec") == [.attachmentName, .link])
    #expect(found("wiki.example") == [.link])
    #expect(found("standup") == [.attachmentNote])
    #expect(found("dana") == [.checklist])
    #expect(found("priya") == [.contact])
    #expect(found("nothing-here").isEmpty)
}

@Test func everyWordMustMatchSomewhere() {
    let records = [
        TaskSearchRecord(item: task("Pay invoice", tags: ["finance"])),
        TaskSearchRecord(item: task("Pay rent")),
    ]
    let groups = TaskSearch.run(records, query: TaskSearchQuery(text: "pay finance"), sort: .newest)
    #expect(titles(groups) == ["Pay invoice"])
}

@Test func tagFiltersRequireAllTagsCaseInsensitively() {
    let records = [
        TaskSearchRecord(item: task("A", tags: ["Work", "urgent"])),
        TaskSearchRecord(item: task("B", tags: ["work"])),
        TaskSearchRecord(item: task("C")),
    ]
    let byChip = TaskSearch.run(records, query: TaskSearchQuery(tags: ["work"]), sort: .title)
    #expect(titles(byChip) == ["A", "B"])
    let byText = TaskSearch.run(records, query: TaskSearchQuery(text: "#WORK #urgent"), sort: .title)
    #expect(titles(byText) == ["A"])
}

@Test func dateRangeIncludesPastAndFutureTasksThatOverlap() {
    let jan5 = TestDates.date(2026, 1, 5)
    let records = [
        TaskSearchRecord(item: task("Old done", status: .done,
                                    start: TestDates.date(2025, 12, 1), due: TestDates.date(2025, 12, 2),
                                    completed: TestDates.date(2025, 12, 2))),
        TaskSearchRecord(item: task("Spans range",
                                    start: TestDates.date(2026, 1, 1), due: TestDates.date(2026, 1, 20))),
        TaskSearchRecord(item: task("Future", start: TestDates.date(2026, 3, 1), due: TestDates.date(2026, 3, 2))),
    ]
    let range = jan5...TestDates.date(2026, 1, 9)
    #expect(titles(TaskSearch.run(records, query: TaskSearchQuery(dateRange: range), sort: .title)) == ["Spans range"])

    let all = TaskSearch.run(records, query: TaskSearchQuery(), sort: .oldest)
    #expect(titles(all) == ["Old done", "Spans range", "Future"])
}

@Test func scopeSeparatesOpenFromClosedAndProjectsAreHidden() {
    let records = [
        TaskSearchRecord(item: task("Open")),
        TaskSearchRecord(item: task("Done", status: .done, completed: TestDates.monday)),
        TaskSearchRecord(item: task("Cancelled", status: .cancelled)),
        TaskSearchRecord(item: task("A project", kind: .project)),
    ]
    #expect(titles(TaskSearch.run(records, query: TaskSearchQuery(scope: .open), sort: .title)) == ["Open"])
    #expect(titles(TaskSearch.run(records, query: TaskSearchQuery(scope: .done), sort: .title)) == ["Cancelled", "Done"])
    #expect(titles(TaskSearch.run(records, query: TaskSearchQuery(), sort: .title)).contains("A project") == false)
}

@Test func groupByTagListsEachTagAlphabeticallyThenUntagged() {
    let records = [
        TaskSearchRecord(item: task("Both", tags: ["work", "Home"])),
        TaskSearchRecord(item: task("Work only", tags: ["work"])),
        TaskSearchRecord(item: task("No tags")),
    ]
    let groups = TaskSearch.run(records, query: TaskSearchQuery(), sort: .tag)
    #expect(groups.map(\.title) == ["#Home", "#work", "No tag"])
    #expect(groups[0].results.map(\.item.title) == ["Both"])
    #expect(Set(groups[1].results.map(\.item.title)) == ["Both", "Work only"])
    #expect(TaskSearch.allTags(in: records) == ["Home", "work"])
}

@Test func deletedTasksNeverAppear() {
    var gone = task("Gone")
    gone.deletedAt = TestDates.monday
    let groups = TaskSearch.run([TaskSearchRecord(item: gone)], query: TaskSearchQuery(text: "gone"), sort: .newest)
    #expect(titles(groups).isEmpty)
}
