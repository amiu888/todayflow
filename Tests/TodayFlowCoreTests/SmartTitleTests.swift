import Foundation
import Testing
@testable import TodayFlowCore

struct SmartTitleTests {
    @Test func findsChangeAndTicketNumbers() {
        #expect(TicketReference.find(in: ["Approve CHG0012345 tonight"]) == .init(id: "CHG0012345", kind: .change))
        #expect(TicketReference.find(in: ["re: chg0031337 rollback"])?.id == "CHG0031337")
        #expect(TicketReference.find(in: ["Change request #45678 for the DNS move"]) == .init(id: "Change 45678", kind: .change))
        #expect(TicketReference.find(in: ["CR-2041 firewall rule"]) == .init(id: "CR-2041", kind: .change))
        #expect(TicketReference.find(in: ["INC0098765 printer down"]) == .init(id: "INC0098765", kind: .incident))
        #expect(TicketReference.find(in: ["Your request RITM0012001 was approved"])?.kind == .request)
        #expect(TicketReference.find(in: ["https://acme.atlassian.net/browse/OPS-42"]) == .init(id: "OPS-42", kind: .jira))
        #expect(TicketReference.find(in: ["[WEB-7] Fix login"])?.id == "WEB-7")
        #expect(TicketReference.find(in: ["Ticket #48213 laptop swap"]) == .init(id: "Ticket 48213", kind: .ticket))
        // A change number wins over an incident in the same text.
        #expect(TicketReference.find(in: ["INC0011111 caused by CHG0022222"])?.id == "CHG0022222")
    }

    @Test func ignoresThingsThatOnlyLookLikeTickets() {
        #expect(TicketReference.find(in: ["Save the file as UTF-8"]) == nil)
        #expect(TicketReference.find(in: ["ISO-9001 audit next week"]) == nil)
        #expect(TicketReference.find(in: ["Lunch at 12:30, room 4"]) == nil)
    }

    @Test func emailSubjectsAreCleanedAndNumbersGoFirst() {
        #expect(SmartTitle.cleanSubject("RE: FW: Fwd:  Budget   for Q3") == "Budget for Q3")
        let email = RecognizedObject(
            type: .email, displayName: "Approve patch window", suggestedTitle: "RE: Approve patch window",
            previewText: "Hi, please approve CHG0045678 before Friday."
        )
        #expect(SmartTitle.inferredTitle(for: [email]) == "CHG0045678: Approve patch window")
        // Already in the subject: not repeated.
        let already = RecognizedObject(type: .email, displayName: "x", suggestedTitle: "CHG0045678 approval needed")
        #expect(SmartTitle.inferredTitle(for: [already]) == "CHG0045678 approval needed")
    }

    @Test func plainCaptureUsesTheRules() {
        let link = RecognizedObject(
            type: .url, displayName: "OPS-42 Rotate keys", reference: "https://acme.atlassian.net/browse/OPS-42",
            metadata: ["jiraIssueKey": "OPS-42"], suggestedTitle: "Rotate keys"
        )
        #expect(CaptureDraftBuilder().build(objects: [link]).title == "OPS-42: Rotate keys")
    }

    @Test func kindKeysSeparateSourcesAndSites() {
        let outlook = RecognizedObject(type: .email, displayName: "a", sourceApp: "com.microsoft.Outlook")
        let change = RecognizedObject(type: .email, displayName: "CHG0012345", sourceApp: "com.microsoft.Outlook")
        let site = RecognizedObject(type: .url, displayName: "x", reference: "https://www.example.com/page")
        #expect(SmartTitle.kindKey(for: [outlook]) == "email|com.microsoft.outlook")
        #expect(SmartTitle.kindKey(for: [change]) == "email|change|com.microsoft.outlook")
        #expect(SmartTitle.kindKey(for: [site]) == "url|example.com")
    }

    @Test func examplesKeepCorrectionsFirst_andAreCappedPerKind() async {
        let store = TitleExampleStore(settings: InMemorySettingRepository())
        await store.record(TitleExample(kindKey: "email", objectName: "a", suggestedTitle: "Same", finalTitle: "Same"))
        await store.record(TitleExample(kindKey: "email", objectName: "b", suggestedTitle: "Reply to Bob", finalTitle: "Send Bob the Q3 numbers"))
        await store.record(TitleExample(kindKey: "url", objectName: "c", suggestedTitle: "x", finalTitle: "y"))
        let email = await store.examples(for: "email")
        #expect(email.map(\.finalTitle) == ["Send Bob the Q3 numbers", "Same"])
        for index in 0..<20 {
            await store.record(TitleExample(kindKey: "email", objectName: "\(index)", suggestedTitle: "s", finalTitle: "f\(index)"))
        }
        #expect(await store.all().filter { $0.kindKey == "email" }.count == TitleExampleStore.perKind)
        #expect(await store.examples(for: "url").count == 1)
    }

    // MARK: - AI titles

    @Test func aTicketNumberTheModelMadeUp_isDropped() {
        let chat = RecognizedObject(type: .image, displayName: "Screenshot", previewText: "Maria: Please renew the parking permit")
        #expect(SmartTitle.fromAI("CHG001: Renew parking permit", objects: [chat]) == "Renew parking permit")
        #expect(SmartTitle.fromAI("ABC-12 - Renew parking permit", objects: [chat]) == "Renew parking permit")
        #expect(SmartTitle.fromAI("[TKT99] Renew parking permit", objects: [chat]) == "[TKT99] Renew parking permit")
    }

    @Test func aRealTicketNumber_staysInFront() {
        let change = RecognizedObject(type: .email, displayName: "CHG0012345 approval", previewText: "Please approve CHG0012345")
        #expect(SmartTitle.fromAI("Approve firewall change", objects: [change]) == "CHG0012345: Approve firewall change")
        #expect(SmartTitle.fromAI("CHG0012345: Approve firewall change", objects: [change]) == "CHG0012345: Approve firewall change")
        let jira = RecognizedObject(type: .url, displayName: "Fix login", metadata: ["jiraKey": "WEB-42"])
        #expect(SmartTitle.fromAI("WEB-42: Fix login", objects: [jira]).hasPrefix("WEB-42"))
    }

    @Test func titlesThatOnlyLookLikeNumbers_areKept() {
        let note = RecognizedObject(type: .text, displayName: "note", previewText: "Book flights")
        #expect(SmartTitle.fromAI("Book flights for 2 people", objects: [note]) == "Book flights for 2 people")
    }
}
