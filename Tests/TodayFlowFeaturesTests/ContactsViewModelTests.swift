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

@Suite("ContactsViewModel group hierarchy")
@MainActor
struct ContactsViewModelGroupHierarchyTests {
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

    @Test func addSubgroupNestsUnderTopLevelParent() async {
        let (model, repository, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })

        await model.addGroup(name: "VIP", parentId: customers.id)

        let vip = try! #require(model.groups.first { $0.name == "VIP" })
        #expect(vip.parentId == customers.id)
        #expect(model.topLevelGroups.map(\.name) == ["Customers"])
        #expect(model.childGroups(of: customers).map(\.name) == ["VIP"])
        #expect(!model.topLevelGroups.contains(where: { $0.id == vip.id }))
        let stored = try! #require((await repository.groups()).first { $0.name == "VIP" })
        #expect(stored.parentId == customers.id)
    }

    @Test func addSubgroupOfSubgroupIsRejected() async {
        let (model, _, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })
        await model.addGroup(name: "VIP", parentId: customers.id)
        let vip = try! #require(model.groups.first { $0.name == "VIP" })
        let countBefore = model.groups.count

        await model.addGroup(name: "Deep", parentId: vip.id)

        #expect(model.groups.count == countBefore)
        #expect(model.groups.first { $0.name == "Deep" } == nil)
        #expect(model.lastMessage == "Groups can only be two levels deep.")
    }

    @Test func moveTopLevelGroupUnderAnotherTopLevelGroupReparentsIt() async {
        let (model, repository, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        await model.addGroup(name: "Vendors")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })
        let vendors = try! #require(model.groups.first { $0.name == "Vendors" })

        await model.moveGroup(customers, toParent: vendors.id)

        #expect(Set(model.topLevelGroups.map(\.name)) == ["Vendors"])
        #expect(model.childGroups(of: vendors).map(\.name) == ["Customers"])
        #expect(model.lastMessage == "Moved Customers under Vendors.")
        let stored = try! #require((await repository.groups()).first { $0.name == "Customers" })
        #expect(stored.parentId == vendors.id)

        await model.moveGroup(stored, toParent: nil)

        #expect(Set(model.topLevelGroups.map(\.name)) == ["Customers", "Vendors"])
        #expect(await repository.groups().first { $0.name == "Customers" }?.parentId == nil)
    }

    @Test func groupWithSubgroupsCannotBecomeSubgroup() async {
        let (model, repository, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        await model.addGroup(name: "Vendors")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })
        let vendors = try! #require(model.groups.first { $0.name == "Vendors" })
        await model.addGroup(name: "VIP", parentId: customers.id)

        await model.moveGroup(customers, toParent: vendors.id)

        let stored = try! #require((await repository.groups()).first { $0.name == "Customers" })
        #expect(stored.parentId == nil)
        #expect(Set(model.topLevelGroups.map(\.name)) == ["Customers", "Vendors"])
        #expect(model.lastMessage == "A group with subgroups cannot become a subgroup.")
    }

    @Test func deleteGroupReparentsSubgroupsToTopLevel() async {
        let (model, repository, _) = make()
        await model.load()
        await model.addGroup(name: "Customers")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })
        await model.addGroup(name: "VIP", parentId: customers.id)
        let vip = try! #require(model.groups.first { $0.name == "VIP" })
        let jane = Contact(firstName: "Jane", lastName: "Doe")
        try! await repository.save(jane)
        try! await repository.setGroups([vip.id], for: jane.id)
        await model.load()

        await model.deleteGroup(customers)
        await model.load()

        let stored = await repository.groups()
        #expect(stored.first { $0.name == "Customers" } == nil)
        let storedVip = try! #require(stored.first { $0.name == "VIP" })
        #expect(storedVip.parentId == nil)
        #expect(await repository.groupIds(for: jane.id) == [vip.id])
        #expect(model.topLevelGroups.map(\.name) == ["VIP"])
    }
}

#if canImport(AppKit)
@Suite("ContactsViewModel contact drag and drop")
@MainActor
struct ContactsViewModelDragTests {
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

    /// Seeds Customers + Vendors + Personal with Jane a member of the first two.
    private func seedContactInTwoGroups(
        _ repository: InMemoryContactRepository
    ) async -> (Customers: UUIDv7, Vendors: UUIDv7, Personal: UUIDv7, Jane: Contact) {
        let customers = ContactGroup(name: "Customers")
        let vendors = ContactGroup(name: "Vendors")
        let personal = ContactGroup(name: "Personal")
        let jane = Contact(firstName: "Jane", lastName: "Doe")
        try! await repository.saveGroup(customers)
        try! await repository.saveGroup(vendors)
        try! await repository.saveGroup(personal)
        try! await repository.save(jane)
        try! await repository.setGroups([customers.id, vendors.id], for: jane.id)
        return (customers.id, vendors.id, personal.id, jane)
    }

    @Test func draggingFromOneGroupToAnotherMovesMembership() async {
        let (model, repository, _) = make()
        let (customers, vendors, _, jane) = await seedContactInTwoGroups(repository)
        await model.load()

        let payload = ContactDragPayload(contactId: jane.id, sourceGroupId: customers)
        await model.moveContact(payload, into: vendors)

        #expect(await repository.groupIds(for: jane.id) == [vendors])
        #expect(model.groups(for: jane).map(\.name) == ["Vendors"])
        #expect(model.lastMessage == "Moved Jane Doe to Vendors.")
    }

    @Test func draggingFromAllContactsAddsWithoutRemovingExisting() async {
        let (model, repository, _) = make()
        let (customers, vendors, personal, jane) = await seedContactInTwoGroups(repository)
        await model.load()

        let payload = ContactDragPayload(contactId: jane.id, sourceGroupId: nil)
        await model.moveContact(payload, into: personal)

        #expect(
            Set(await repository.groupIds(for: jane.id))
                == [customers, vendors, personal]
        )
    }

    @Test func droppingOnNoGroupRemovesSourceMembership() async {
        let (model, repository, _) = make()
        let (customers, vendors, _, jane) = await seedContactInTwoGroups(repository)
        await model.load()

        let payload = ContactDragPayload(contactId: jane.id, sourceGroupId: customers)
        await model.moveContact(payload, into: nil)

        #expect(await repository.groupIds(for: jane.id) == [vendors])
        #expect(model.lastMessage == "Removed Jane Doe from the group.")
    }

    @Test func droppingOnAllContactsFromAllContactsIsANoOp() async {
        let (model, repository, _) = make()
        let (customers, vendors, _, jane) = await seedContactInTwoGroups(repository)
        await model.load()

        let payload = ContactDragPayload(contactId: jane.id, sourceGroupId: nil)
        await model.moveContact(payload, into: nil)

        #expect(
            Set(await repository.groupIds(for: jane.id)) == [customers, vendors]
        )
        #expect(model.lastMessage == nil)
    }
}
#endif

@Suite("ContactsViewModel group contact counts")
@MainActor
struct ContactsViewModelGroupCountTests {
    @Test func parentCountIncludesChildOnlyContactsWithoutDoubleCounting() async {
        let contacts = InMemoryContactRepository()
        let workItems = InMemoryWorkItemRepository()
        let model = ContactsViewModel(
            repository: contacts,
            workItems: workItems,
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        await model.load()
        await model.addGroup(name: "Customers")
        let customers = try! #require(model.groups.first { $0.name == "Customers" })
        await model.addGroup(name: "VIP", parentId: customers.id)
        let vip = try! #require(model.groups.first { $0.name == "VIP" })

        let jane = Contact(firstName: "Jane") // VIP only
        let bob = Contact(firstName: "Bob") // Customers and VIP
        let amy = Contact(firstName: "Amy") // Customers only
        for contact in [jane, bob, amy] { try! await contacts.save(contact) }
        try! await contacts.setGroups([vip.id], for: jane.id)
        try! await contacts.setGroups([customers.id, vip.id], for: bob.id)
        try! await contacts.setGroups([customers.id], for: amy.id)
        await model.load()

        // Jane is reached through VIP; Bob is in both but must be counted once.
        #expect(model.contactCount(in: customers) == 3)
        #expect(model.contactCount(in: vip) == 2)
        #expect(Set(model.groups(for: bob).map(\.id)) == [customers.id, vip.id])
    }
}
