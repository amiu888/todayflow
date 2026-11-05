import Foundation
import Observation
import TodayFlowDesign
import TodayFlowCore

/// State and actions for the contacts window: groups, search, duplicates,
/// imports, and task associations.
@MainActor
@Observable
public final class ContactsViewModel {
    public private(set) var contacts: [Contact] = []
    public private(set) var groups: [ContactGroup] = []
    public private(set) var contactGroupIds: [UUIDv7: Set<UUIDv7>] = [:]
    public private(set) var duplicates: [[Contact]] = []
    public private(set) var selectedContactTasks: [WorkItem] = []
    public private(set) var isWorking = false
    public private(set) var lastError: String?

    public var selectedGroupID: UUIDv7?
    public var selectedContactID: UUIDv7?
    public var searchText = ""

    // Import preview state.
    public var importFilter = ContactImportFilter()
    public private(set) var pendingImportRecords: [ImportedContact] = []
    public private(set) var importPlan: ContactImportPlan?
    public private(set) var importSourceLabel = ""
    public var isImporting = false

    @ObservationIgnored private let repository: any ContactRepository
    @ObservationIgnored private let workItems: any WorkItemRepository
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date
    public var onOpenTask: (@MainActor (UUIDv7) -> Void)?

    public init(
        repository: any ContactRepository,
        workItems: any WorkItemRepository,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now },
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        self.repository = repository
        self.workItems = workItems
        self.deviceId = deviceId
        self.clock = clock
        self.onOpenTask = onOpenTask
    }

    public var selectedContact: Contact? {
        guard let selectedContactID else { return nil }
        return contacts.first { $0.id == selectedContactID }
    }

    public var filteredContacts: [Contact] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return contacts.filter { contact in
            if let selectedGroupID,
               !(contactGroupIds[contact.id] ?? []).contains(selectedGroupID)
            {
                return false
            }
            guard !query.isEmpty else { return true }
            return contact.searchText.contains(query)
        }
    }

    public func groups(for contact: Contact) -> [ContactGroup] {
        let ids = contactGroupIds[contact.id] ?? []
        return groups.filter { ids.contains($0.id) }
    }

    public func contactCount(in group: ContactGroup) -> Int {
        contactGroupIds.values.filter { $0.contains(group.id) }.count
    }

    public func load() async {
        isWorking = true
        defer { isWorking = false }
        contacts = await repository.contacts()
        groups = await repository.groups()
        // One query for every group membership instead of one per contact.
        contactGroupIds = await repository.groupMemberships()
            .mapValues { Set($0) }
        duplicates = ContactDeduplicator.duplicateGroups(in: contacts)
        if let selectedContactID, !contacts.contains(where: { $0.id == selectedContactID }) {
            self.selectedContactID = contacts.first?.id
        } else if selectedContactID == nil {
            selectedContactID = contacts.first?.id
        }
        if let selectedContactID {
            await loadTasks(for: selectedContactID)
        }
    }

    public func selectContact(_ id: UUIDv7?) async {
        selectedContactID = id
        if let id { await loadTasks(for: id) } else { selectedContactTasks = [] }
    }

    private func loadTasks(for contactId: UUIDv7) async {
        let ids = Set(await repository.taskIds(forContact: contactId))
        let all = await workItems.allItems()
        selectedContactTasks = all
            .filter { ids.contains($0.id) }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    public func save(_ draft: Contact, groupIds: Set<UUIDv7>) async {
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            var contact = draft
            let now = clock()
            if let existing = contacts.first(where: { $0.id == draft.id }) {
                contact.version = existing.version + 1
                contact.createdAt = existing.createdAt
            } else {
                contact.version = 1
                contact.createdAt = now
            }
            contact.updatedAt = now
            contact.deviceId = deviceId
            try await repository.save(contact)
            try await repository.setGroups(Array(groupIds), for: contact.id)
            await load()
            selectedContactID = contact.id
            await loadTasks(for: contact.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func delete(_ contact: Contact) async {
        do {
            try await repository.delete(contact.id, at: clock())
            if selectedContactID == contact.id { selectedContactID = nil }
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func addGroup(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lastOrder = groups.map(\.sortOrder)
            .max(by: FractionalIndex.isLessThan)
        let order = FractionalIndex.midpoint(lastOrder, nil)
        let now = clock()
        let group = ContactGroup(
            name: trimmed,
            colorHex: DesignTokens.TrayPalette.colorHex(at: groups.count),
            sortOrder: order,
            createdAt: now,
            updatedAt: now,
            deviceId: deviceId
        )
        try? await repository.saveGroup(group)
        await load()
    }

    public func renameGroup(_ group: ContactGroup, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = group
        updated.name = trimmed
        updated.updatedAt = clock()
        updated.version += 1
        try? await repository.saveGroup(updated)
        await load()
    }

    public func deleteGroup(_ group: ContactGroup) async {
        try? await repository.deleteGroup(group.id)
        if selectedGroupID == group.id { selectedGroupID = nil }
        await load()
    }

    public func refreshDuplicates() {
        duplicates = ContactDeduplicator.duplicateGroups(in: contacts)
    }

    public func merge(_ contactsToMerge: [Contact], into primary: Contact) async {
        guard contactsToMerge.count > 1 else { return }
        let now = clock()
        let merged = ContactMerger.merge(contactsToMerge, primary: primary, at: now)
        let sourceIds = contactsToMerge.map(\.id).filter { $0 != primary.id }
        do {
            try await repository.merge(sourceIds, into: merged, at: now)
            await load()
            selectedContactID = primary.id
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func autoMergeDuplicates() async {
        for group in duplicates {
            guard let primary = group.first else { continue }
            await merge(group, into: primary)
        }
        refreshDuplicates()
    }

    // MARK: - Import

    public func prepareImport(_ records: [ImportedContact], source: String) {
        pendingImportRecords = records
        importSourceLabel = source
        recomputeImportPlan()
    }

    public func recomputeImportPlan() {
        guard !pendingImportRecords.isEmpty else {
            importPlan = nil
            return
        }
        importPlan = ContactImporter().plan(
            importing: pendingImportRecords,
            existing: contacts,
            existingGroups: groups,
            filter: importFilter,
            deviceId: deviceId,
            now: clock()
        )
    }

    public func clearImport() {
        pendingImportRecords = []
        importPlan = nil
        importSourceLabel = ""
        importFilter = ContactImportFilter()
    }

    public func applyImport() async {
        guard !pendingImportRecords.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            // Recompute against the latest store state: the preview may be
            // minutes old, and importing against a stale snapshot duplicates
            // contacts or overwrites newer edits.
            let freshContacts = await repository.contacts()
            let freshGroups = await repository.groups()
            let plan = ContactImporter().plan(
                importing: pendingImportRecords,
                existing: freshContacts,
                existingGroups: freshGroups,
                filter: importFilter,
                deviceId: deviceId,
                now: clock()
            )
            guard !plan.contacts.isEmpty else { return }
            try await repository.applyImport(plan)
            clearImport()
            await load()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

