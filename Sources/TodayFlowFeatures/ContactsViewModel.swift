import Foundation
import Observation
import TodayFlowDesign
import TodayFlowCore
import TodayFlowRecognition

/// State and actions for the contacts window: groups, search, duplicates,
/// imports, and task associations.
@MainActor
@Observable
public final class ContactsViewModel {
    public private(set) var contacts: [Contact] = []
    public private(set) var groups: [ContactGroup] = []
    public private(set) var contactGroupIds: [UUIDv7: Set<UUIDv7>] = [:]
    /// Derived lookups rebuilt once per load so row rendering and sidebar
    /// badges stay O(1) instead of scanning every contact per row.
    public private(set) var contactGroups: [UUIDv7: [ContactGroup]] = [:]
    public private(set) var groupContactCounts: [UUIDv7: Int] = [:]
    public private(set) var duplicates: [[Contact]] = []
    public private(set) var selectedContactTasks: [WorkItem] = []
    public private(set) var isWorking = false
    public private(set) var lastError: String?
    public private(set) var lastMessage: String?

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
    @ObservationIgnored private var messageTask: Task<Void, Never>?
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

    public var topLevelGroups: [ContactGroup] {
        groups.filter { $0.parentId == nil }
    }

    public func childGroups(of group: ContactGroup) -> [ContactGroup] {
        groups.filter { $0.parentId == group.id }
    }

    public func groupAndDescendantIds(_ id: UUIDv7) -> Set<UUIDv7> {
        guard let group = groups.first(where: { $0.id == id }) else { return [id] }
        var ids: Set<UUIDv7> = [id]
        if group.parentId == nil {
            for child in childGroups(of: group) { ids.insert(child.id) }
        }
        return ids
    }

    public func sourceGroupId(for contact: Contact) -> UUIDv7? {
        guard let selectedGroupID,
              (contactGroupIds[contact.id] ?? []).contains(selectedGroupID)
        else { return nil }
        return selectedGroupID
    }

    public var filteredContacts: [Contact] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedGroups = selectedGroupID.map(groupAndDescendantIds)
        return contacts.filter { contact in
            if let allowedGroups,
               (contactGroupIds[contact.id] ?? []).isDisjoint(with: allowedGroups)
            {
                return false
            }
            guard !query.isEmpty else { return true }
            return contact.searchText.contains(query)
        }
    }

    public func groups(for contact: Contact) -> [ContactGroup] {
        contactGroups[contact.id] ?? []
    }

    public func contactCount(in group: ContactGroup) -> Int {
        groupContactCounts[group.id] ?? 0
    }

    public func load() async {
        isWorking = true
        defer { isWorking = false }
        contacts = await repository.contacts()
        groups = await repository.groups()
        // One query for every group membership instead of one per contact.
        contactGroupIds = await repository.groupMemberships()
            .mapValues { Set($0) }
        rebuildDerivedLookups()
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

    private func rebuildDerivedLookups() {
        let groupById = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        let order = Dictionary(
            uniqueKeysWithValues: groups.enumerated().map { ($1.id, $0) }
        )
        var byContact: [UUIDv7: [ContactGroup]] = [:]
        var counts: [UUIDv7: Int] = [:]
        for (contactId, ids) in contactGroupIds {
            let matched = ids.compactMap { groupById[$0] }
                .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            if !matched.isEmpty {
                byContact[contactId] = matched
            }
            // Count a contact once per group. A parent also counts contacts
            // that only belong to one of its subgroups.
            var counted: Set<UUIDv7> = []
            for group in matched {
                counted.insert(group.id)
                if let parentId = group.parentId, groupById[parentId] != nil {
                    counted.insert(parentId)
                }
            }
            for id in counted {
                counts[id, default: 0] += 1
            }
        }
        contactGroups = byContact
        groupContactCounts = counts
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

    public func addGroup(name: String, parentId: UUIDv7? = nil) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let parentId {
            guard let parent = groups.first(where: { $0.id == parentId }),
                  parent.parentId == nil
            else {
                flash("Groups can only be two levels deep.")
                return
            }
        }
        let siblings = groups.filter { $0.parentId == parentId }
        let lastOrder = siblings.map(\.sortOrder)
            .max(by: FractionalIndex.isLessThan)
        let order = FractionalIndex.midpoint(lastOrder, nil)
        let now = clock()
        let group = ContactGroup(
            name: trimmed,
            parentId: parentId,
            colorHex: DesignTokens.TrayPalette.colorHex(at: groups.count),
            sortOrder: order,
            createdAt: now,
            updatedAt: now,
            deviceId: deviceId
        )
        try? await repository.saveGroup(group)
        await load()
    }

    /// Reparents a group. Only two levels are allowed, and a group that owns
    /// subgroups cannot itself become a subgroup.
    public func moveGroup(_ group: ContactGroup, toParent parentId: UUIDv7?) async {
        if let parentId {
            guard parentId != group.id,
                  let parent = groups.first(where: { $0.id == parentId }),
                  parent.parentId == nil
            else {
                flash("Choose a top-level group.")
                return
            }
            guard !groups.contains(where: { $0.parentId == group.id }) else {
                flash("A group with subgroups cannot become a subgroup.")
                return
            }
        }
        var updated = group
        updated.parentId = parentId
        updated.updatedAt = clock()
        updated.version += 1
        try? await repository.saveGroup(updated)
        await load()
        if parentId == nil {
            flash("Moved \(group.name) to the top level.")
        } else if let parent = groups.first(where: { $0.id == parentId }) {
            flash("Moved \(group.name) under \(parent.name).")
        }
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
        flash("Deleted group \(group.name). Subgroups moved to the top level.")
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

    /// Moves a contact between groups. A drag from All Contacts adds the group
    /// without removing any other membership; a drag from a group moves it.
    public func moveContact(_ payload: ContactDragPayload, into groupId: UUIDv7?) async {
        guard let contact = contacts.first(where: { $0.id == payload.contactId })
        else { return }
        var groupIds = Set(await repository.groupIds(for: contact.id))
        if let source = payload.sourceGroupId, source != groupId {
            groupIds.remove(source)
        }
        if let groupId {
            groupIds.insert(groupId)
        } else if payload.sourceGroupId == nil {
            return
        }
        do {
            try await repository.setGroups(Array(groupIds), for: contact.id)
            await load()
            if let groupId, let group = groups.first(where: { $0.id == groupId }) {
                flash("Moved \(contact.displayName) to \(group.name).")
            } else {
                flash("Removed \(contact.displayName) from the group.")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Imports vCard/CSV/text contacts dropped from another app. Matches merge
    /// by email/phone; the target group is added to every touched contact.
    public func importDroppedContacts(
        _ providers: [NSItemProvider],
        into groupId: UUIDv7?
    ) async {
        let records = await ContactProviderImporter.contacts(from: providers)
        guard !records.isEmpty else {
            flash("No contact details found in that drop.")
            return
        }
        let freshContacts = await repository.contacts()
        let freshGroups = await repository.groups()
        var plan = ContactImporter().plan(
            importing: records,
            existing: freshContacts,
            existingGroups: freshGroups,
            deviceId: deviceId,
            now: clock()
        )
        if let groupId {
            for contact in plan.contacts {
                plan.groupAssignments[contact.id, default: []].append(groupId)
            }
        }
        do {
            try await repository.applyImport(plan)
            await load()
            if let groupId, let group = groups.first(where: { $0.id == groupId }) {
                flash("Added \(plan.importedCount) · merged \(plan.mergedCount) into \(group.name).")
            } else {
                flash("Added \(plan.importedCount) · merged \(plan.mergedCount) contacts.")
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func flash(_ message: String) {
        lastMessage = message
        messageTask?.cancel()
        messageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.lastMessage = nil
        }
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

