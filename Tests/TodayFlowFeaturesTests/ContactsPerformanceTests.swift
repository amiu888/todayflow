import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

/// The contacts window must stay responsive at address-book scale. The view
/// model rebuilds derived lookups once per load so row rendering and sidebar
/// badges are O(1) afterwards.
@Suite("Contacts performance")
@MainActor
struct ContactsPerformanceTests {
    @Test func loadAndFilterStayFastWithFiveThousandContacts() async throws {
        let contacts = (0..<5_000).map { index in
            Contact(
                firstName: "Person",
                lastName: "\(index)",
                company: "Company \(index % 40)",
                emails: ["person\(index)@example.com"],
                phones: ["+1 555 \(String(format: "%07d", index))"],
                source: "performance"
            )
        }
        let parents = (0..<30).map { ContactGroup(name: "Parent \($0)") }
        let children = (0..<30).map {
            ContactGroup(name: "Child \($0)", parentId: parents[$0].id)
        }
        let allGroups = parents + children

        var assignments: [UUIDv7: [UUIDv7]] = [:]
        for (index, contact) in contacts.enumerated() {
            // Half the contacts live only in a child group, so parent counts
            // exercise the descendant roll-up.
            let group = index < 2_500
                ? parents[index % parents.count]
                : children[(index - 2_500) % children.count]
            assignments[contact.id] = [group.id]
        }
        let plan = ContactImportPlan(
            contacts: contacts,
            newGroups: allGroups,
            groupAssignments: assignments,
            importedCount: contacts.count
        )
        let repository = InMemoryContactRepository()
        try await repository.applyImport(plan)
        let model = ContactsViewModel(
            repository: repository,
            workItems: InMemoryWorkItemRepository(),
            deviceId: "performance",
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        let loadStart = Date.now
        await model.load()
        let loadElapsed = Date.now.timeIntervalSince(loadStart)

        model.searchText = "person4999"
        let filterStart = Date.now
        let filtered = model.filteredContacts
        let filterElapsed = Date.now.timeIntervalSince(filterStart)

        #expect(model.contacts.count == 5_000)
        #expect(model.groups.count == 60)
        #expect(model.contactCount(in: parents[0]) == 168)
        #expect(filtered.count == 1)
        #expect(loadElapsed < 2.0, "contacts load took \(loadElapsed)s")
        #expect(filterElapsed < 0.1, "contacts search took \(filterElapsed)s")
    }
}
