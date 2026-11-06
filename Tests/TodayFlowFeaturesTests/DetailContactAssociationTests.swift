import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@Suite("Detail contacts")
@MainActor
struct DetailContactAssociationTests {
    @Test func createAndLinkContactFromTheTaskDetail() async throws {
        let items = InMemoryWorkItemRepository()
        let contacts = InMemoryContactRepository()
        let item = WorkItem(title: "Kickoff")
        await items.seed(item)
        let model = DetailViewModel(
            itemId: item.id,
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            contactRepository: contacts
        )
        await model.load()

        let created = await model.createAndLinkContact(
            firstName: "Jane",
            email: "jane@acme.com",
            phone: "+1 555 0100"
        )

        let contact = try #require(created)
        #expect(contact.firstName == "Jane")
        #expect(model.contacts.map(\.id) == [contact.id])
        #expect(model.allContacts.map(\.id).contains(contact.id))
        #expect(await contacts.contact(contact.id) != nil)
    }

    @Test func createAndLinkReusesAMatchingContact() async throws {
        let items = InMemoryWorkItemRepository()
        let contacts = InMemoryContactRepository()
        let item = WorkItem(title: "Kickoff")
        let jane = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        await items.seed(item)
        try await contacts.save(jane)
        let model = DetailViewModel(
            itemId: item.id,
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            contactRepository: contacts
        )
        await model.load()

        let linked = await model.createAndLinkContact(
            firstName: "J.",
            email: "JANE@acme.com"
        )

        #expect(linked?.id == jane.id)
        #expect(model.contacts.map(\.id) == [jane.id])
        #expect(await contacts.contacts().count == 1)
    }

    @Test func taskCanHaveManyContactsAndRemoveOne() async {
        let items = InMemoryWorkItemRepository()
        let contacts = InMemoryContactRepository()
        let item = WorkItem(title: "Kickoff")
        let jane = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        let bob = Contact(firstName: "Bob", emails: ["bob@acme.com"])
        await items.seed(item)
        try? await contacts.save(jane)
        try? await contacts.save(bob)

        let model = DetailViewModel(
            itemId: item.id,
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            contactRepository: contacts
        )
        await model.load()
        await model.addContact(jane.id)
        await model.addContact(bob.id)
        #expect(model.contacts.map(\.displayName).sorted() == ["Bob", "Jane"])

        await model.removeContact(jane.id)
        #expect(model.contacts.map(\.displayName) == ["Bob"])
    }
}
