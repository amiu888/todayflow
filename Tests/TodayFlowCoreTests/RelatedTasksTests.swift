import Foundation
import Testing
@testable import TodayFlowCore

@Suite("Related tasks")
struct RelatedTasksTests {
    private func record(
        _ title: String, note: String = "", tags: [String] = [], contacts: [String] = [],
        email: String? = nil, kind: WorkItem.Kind = .task
    ) -> TaskSearchRecord {
        let item = WorkItem(kind: kind, title: title, descriptionMd: note, tags: tags)
        let attachments = email.map { [Attachment(itemId: item.id, kind: .email, displayName: $0)] } ?? []
        return TaskSearchRecord(item: item, attachments: attachments, contactNames: contacts)
    }

    @Test func findsTicketNumbers() {
        #expect(RelatedTasks.tickets(in: "CHG0012345 - remove Java, see CTASK0012399 and ABC-42")
            == ["CHG0012345", "CTASK0012399", "ABC-42"])
        #expect(RelatedTasks.tickets(in: "Meet at 10:30, room 4B").isEmpty)
    }

    @Test func emailThreadsIgnoreReplyPrefixes() {
        #expect(RelatedTasks.threadKey("RE: FW: Java on db servers") == RelatedTasks.threadKey("Java on db servers"))
    }

    @Test func ranksByWhatTheyShare() {
        let target = record("CHG0012345 - remove Java", tags: ["db-server-01"], contacts: ["Alex Morgan"],
                            email: "Java on db servers")
        let sameTicket = record("Test rollback", note: "Part of CHG0012345")
        let sameThread = record("Reply to Alex", email: "RE: Java on db servers")
        let sameContact = record("Lunch", contacts: ["Alex Morgan"])
        let sameTag = record("Disk space", tags: ["db-server-01"])
        let unrelated = record("Book dentist")
        let project = record("CHG0012345 project", kind: .project)

        let suggestions = RelatedTasks.suggest(
            for: target, among: [target, unrelated, sameTag, sameContact, sameThread, sameTicket, project]
        )
        #expect(suggestions.map(\.item.title) == ["Test rollback", "Reply to Alex", "Lunch", "Disk space"])
        #expect(suggestions[0].reasons == ["Same ticket CHG0012345"])
        #expect(suggestions[0].isStrong)
        #expect(suggestions[1].reasons.contains("Same email thread"))
        #expect(!suggestions[2].isStrong) // a shared contact alone is a hint, not pre-selected
    }

    @Test func tagsOnMostTasksDoNotCount() {
        let target = record("A thing", tags: ["work"])
        let others = (1...12).map { record("Other \($0)", tags: ["work"]) }
        #expect(RelatedTasks.suggest(for: target, among: [target] + others).isEmpty)
    }

    @Test func namesTheProjectAfterTheSharedTicket() {
        let target = record("Remove Java", note: "CHG0012345")
        let other = record("Rollback plan CHG0012345")
        #expect(RelatedTasks.projectName(for: target, with: [other]) == "CHG0012345")
        let tagged = record("Disk", tags: ["db-server-01"])
        let tagged2 = record("Memory", tags: ["db-server-01"])
        #expect(RelatedTasks.projectName(for: tagged, with: [tagged2]) == "db-server-01")
    }
}
