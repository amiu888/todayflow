import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@Suite("Contacts window drops")
@MainActor
struct ContactsDropTests {
    private func make() -> (ContactsViewModel, InMemoryContactRepository, InMemoryWorkItemRepository) {
        let contacts = InMemoryContactRepository()
        let workItems = InMemoryWorkItemRepository()
        let model = ContactsViewModel(
            repository: contacts,
            workItems: workItems,
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return (model, contacts, workItems)
    }

    @Test func droppedContacts_withoutAMatch_areAddedAsNew() async {
        let (model, contacts, _) = make()
        try? await contacts.save(Contact(firstName: "Jane", emails: ["jane@acme.com"]))
        await model.importDropped([ImportedContact(firstName: "Bob", emails: ["bob@acme.com"], source: "vcard")], into: nil)
        #expect(await contacts.contacts().count == 2)
        #expect(model.pendingDrops.isEmpty)
    }

    @Test func droppedContacts_withAMatch_waitForAChoice() async {
        let (model, contacts, _) = make()
        let jane = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        try? await contacts.save(jane)
        await model.importDropped([
            ImportedContact(firstName: "Jane", company: "Acme", emails: ["jane@acme.com"], source: "vcard"),
            ImportedContact(firstName: "Jane", emails: ["jane@acme.com"], phones: ["+1 555 0100"], source: "vcard"),
            ImportedContact(firstName: "Bob", emails: ["bob@acme.com"], source: "vcard"),
        ], into: nil)
        // Bob is added; the two Janes wait. Nothing is merged on its own.
        #expect(await contacts.contacts().count == 2)
        #expect(model.pendingDrops.count == 2)
        #expect(model.pendingDropProgress == "1 of 2")
        #expect(await contacts.contact(jane.id)?.company == "")

        await model.resolvePendingDrop(.replace)
        #expect(await contacts.contact(jane.id)?.company == "Acme")
        #expect(model.pendingDropProgress == "2 of 2")

        await model.resolvePendingDrop(.keepBoth)
        #expect(await contacts.contacts().count == 3)
        #expect(model.pendingDrops.isEmpty)
        #expect(model.lastMessage == "Added 2 · replaced 1 contacts.")
    }

    @Test func droppedContacts_canBeSkipped() async {
        let (model, contacts, _) = make()
        try? await contacts.save(Contact(firstName: "Jane", emails: ["jane@acme.com"]))
        await model.importDropped([ImportedContact(firstName: "Jane", emails: ["jane@acme.com"], source: "vcard")], into: nil)
        model.skipPendingDrop()
        #expect(await contacts.contacts().count == 1)
        #expect(model.pendingDrops.isEmpty)
    }
}
