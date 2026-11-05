import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@Suite("Detail contacts")
@MainActor
struct DetailContactAssociationTests {
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
