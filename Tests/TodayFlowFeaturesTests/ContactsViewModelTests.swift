import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@Suite("ContactsViewModel")
@MainActor
struct ContactsViewModelTests {
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

    @Test func loadsSearchesAndFiltersByGroup() async {
        let (model, _, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        let group = try! #require(model.groups.first)

        await model.save(
            Contact(firstName: "Jane", lastName: "Smith", emails: ["jane@acme.com"]),
            groupIds: [group.id]
        )
        await model.save(
            Contact(firstName: "Bob", company: "Other"),
            groupIds: []
        )
        await model.load()
        #expect(model.contacts.count == 2)

        model.searchText = "jane"
        #expect(model.filteredContacts.map(\.firstName) == ["Jane"])

        model.searchText = ""
        model.selectedGroupID = group.id
        #expect(model.filteredContacts.map(\.firstName) == ["Jane"])
        #expect(model.contactCount(in: group) == 1)
    }

    @Test func importPreviewAppliesFiltersAndMergesExistingContacts() async {
        let (model, repository, _) = make()
        let existing = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        try? await repository.save(existing)
        await model.load()

        model.prepareImport(
            [
                ImportedContact(
                    firstName: "Jane",
                    lastName: "Smith",
                    emails: ["JANE@acme.com"],
                    phones: ["555-0100"],
                    source: "outlook"
                ),
                ImportedContact(
                    firstName: "No Email",
                    source: "csv"
                ),
            ],
            source: "Outlook CSV"
        )
        model.importFilter = ContactImportFilter(requireEmail: true)
        model.recomputeImportPlan()

        #expect(model.importPlan?.mergedCount == 1)
        #expect(model.importPlan?.skippedCount == 1)

        await model.applyImport()
        #expect(model.contacts.count == 1)
        #expect(model.contacts.first?.lastName == "Smith")
        #expect(model.contacts.first?.phones == ["555-0100"])
    }

    @Test func duplicateReviewMergesManually() async {
        let (model, repository, _) = make()
        try? await repository.save(Contact(firstName: "Jane", emails: ["jane@acme.com"]))
        try? await repository.save(Contact(firstName: "J.", emails: ["JANE@acme.com"]))
        await model.load()
        let group = try! #require(model.duplicates.first)
        let primary = try! #require(group.first)

        await model.merge(group, into: primary)
        #expect(model.contacts.count == 1)
        #expect(model.duplicates.isEmpty)
    }

    @Test func selectingAContactLoadsItsTasks() async {
        let (model, repository, workItems) = make()
        let contact = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        try? await repository.save(contact)
        let task = WorkItem(title: "Call Jane")
        await workItems.seed(task)
        try? await repository.addContact(contact.id, toTask: task.id)
        await model.load()
        await model.selectContact(contact.id)

        #expect(model.selectedContactTasks.map(\.title) == ["Call Jane"])
    }
}

@Suite("ContactsViewModel integration")
@MainActor
struct ContactsViewModelIntegrationTests {
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

@Test @MainActor
func autoMergeHandlesMultipleDuplicateGroups() async {
    let (model, repository, _) = make()
    try? await repository.save(Contact(firstName: "Jane", emails: ["jane@acme.com"]))
    try? await repository.save(Contact(firstName: "J.", emails: ["JANE@acme.com"]))
    try? await repository.save(Contact(firstName: "Bob", phones: ["555"]))
    try? await repository.save(Contact(firstName: "Robert", phones: ["(555)"]))
    await model.load()
    #expect(model.duplicates.count == 2)

    await model.autoMergeDuplicates()
    #expect(model.contacts.count == 2)
    #expect(model.duplicates.isEmpty)
}

@Test @MainActor
func deletingAContactRemovesItAndItsGroupMembership() async {
    let (model, _, _) = make()
    await model.addGroup(name: "Customers")
    let group = try! #require(model.groups.first)
    await model.save(
        Contact(firstName: "Jane", emails: ["jane@acme.com"]),
        groupIds: [group.id]
    )
    let contact = try! #require(model.contacts.first)

    await model.delete(contact)
    #expect(model.contacts.isEmpty)
    #expect(model.contactCount(in: group) == 0)
}

@Test @MainActor
func applyImportRecomputesAgainstFreshStoreState() async {
    let (model, repository, _) = make()
    await model.load()
    // The repository changes after the window loaded and before Import is applied.
    try? await repository.save(Contact(firstName: "Jane", emails: ["jane@acme.com"]))

    model.prepareImport(
        [
            ImportedContact(
                firstName: "Jane",
                lastName: "Smith",
                emails: ["JANE@acme.com"],
                source: "outlook"
            )
        ],
        source: "Outlook CSV"
    )
    await model.applyImport()

    #expect(model.contacts.count == 1)
    #expect(model.contacts.first?.lastName == "Smith")
}
}

@Suite("ContactsViewModel group ordering")
@MainActor
struct ContactsViewModelGroupOrderTests {
    @Test func newGroupsStillSortAfterDeletion() async {
        let contacts = InMemoryContactRepository()
        let workItems = InMemoryWorkItemRepository()
        let model = ContactsViewModel(repository: contacts, workItems: workItems)
        await model.load()
        await model.addGroup(name: "A")
        await model.addGroup(name: "B")
        let a = try! #require(model.groups.first { $0.name == "A" })
        await model.deleteGroup(a)
        await model.addGroup(name: "C")
        #expect(model.groups.map(\.name) == ["B", "C"])
    }
}
