import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence

@Suite("GRDBContactRepository")
struct GRDBContactRepositoryTests {
    @Test func contactRoundTripsEveryField() async throws {
        let db = try TestDB.inMemory()
        let contact = Contact(
            firstName: "Jane",
            lastName: "Smith",
            company: "Acme",
            jobTitle: "Buyer",
            emails: ["jane@acme.com", "jane@example.com"],
            phones: ["+1 555 0100"],
            notes: "Met at expo",
            source: "outlook",
            externalId: "contact-1",
            createdAt: Date.whole(year: 2026, month: 1, day: 5),
            updatedAt: Date.whole(year: 2026, month: 1, day: 6),
            deviceId: "device-1"
        )
        try await db.contacts.save(contact)

        #expect(await db.contacts.contact(contact.id) == contact)
        #expect(await db.contacts.contacts() == [contact])
    }

    @Test func groupsAndTaskLinksRoundTrip() async throws {
        let db = try TestDB.inMemory()
        let customer = ContactGroup(name: "Customers")
        let vip = ContactGroup(name: "VIP")
        try await db.contacts.saveGroup(customer)
        try await db.contacts.saveGroup(vip)

        let jane = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        let bob = Contact(firstName: "Bob", emails: ["bob@acme.com"])
        try await db.contacts.save(jane)
        try await db.contacts.save(bob)
        try await db.contacts.setGroups([customer.id, vip.id], for: jane.id)
        try await db.contacts.setGroups([customer.id], for: bob.id)

        #expect(await db.contacts.groups().map(\.name).sorted() == ["Customers", "VIP"])
        #expect(await db.contacts.contacts(inGroup: customer.id).count == 2)
        #expect(await db.contacts.contacts(inGroup: vip.id).map(\.id) == [jane.id])
        #expect(Set(await db.contacts.groupIds(for: jane.id)) == [customer.id, vip.id])

        let task = WorkItem(title: "Review contract")
        try await db.workItems.save(task)
        try await db.contacts.addContact(jane.id, toTask: task.id)
        try await db.contacts.addContact(bob.id, toTask: task.id)

        #expect(await db.contacts.contacts(forTask: task.id).count == 2)
        #expect(await db.contacts.taskIds(forContact: jane.id) == [task.id])
        try await db.contacts.removeContact(bob.id, fromTask: task.id)
        #expect(await db.contacts.contacts(forTask: task.id).map(\.id) == [jane.id])
    }

    @Test func mergeMovesGroupsAndTasksAndSoftDeletesSources() async throws {
        let db = try TestDB.inMemory()
        let group = ContactGroup(name: "Customers")
        try await db.contacts.saveGroup(group)
        var primary = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        let duplicate = Contact(firstName: "J.", emails: ["jane@acme.com"], phones: ["555"])
        try await db.contacts.save(primary)
        try await db.contacts.save(duplicate)
        try await db.contacts.setGroups([group.id], for: duplicate.id)
        let task = WorkItem(title: "Call Jane")
        try await db.workItems.save(task)
        try await db.contacts.addContact(duplicate.id, toTask: task.id)

        let merged = ContactMerger.merge([primary, duplicate], primary: primary)
        try await db.contacts.merge([duplicate.id], into: merged, at: .now)

        #expect(await db.contacts.contact(duplicate.id) == nil)
        #expect(await db.contacts.contact(primary.id)?.phones == ["555"])
        #expect(await db.contacts.contacts(inGroup: group.id).map(\.id) == [primary.id])
        #expect(await db.contacts.contacts(forTask: task.id).map(\.id) == [primary.id])
    }
}
