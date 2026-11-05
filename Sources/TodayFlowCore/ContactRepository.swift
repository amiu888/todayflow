import Foundation

/// Local-first contact storage. Contacts, groups, and task associations live
/// in the same SQLite database as work items.
public protocol ContactRepository: Sendable {
    func contacts() async -> [Contact]
    func contact(_ id: UUIDv7) async -> Contact?
    func save(_ contact: Contact) async throws
    /// Soft-deletes the contact and its group/task links.
    func delete(_ id: UUIDv7, at: Date) async throws

    func groups() async -> [ContactGroup]
    func saveGroup(_ group: ContactGroup) async throws
    func deleteGroup(_ id: UUIDv7) async throws

    func groupIds(for contactId: UUIDv7) async -> [UUIDv7]
    func setGroups(_ groupIds: [UUIDv7], for contactId: UUIDv7) async throws
    func contacts(inGroup groupId: UUIDv7) async -> [Contact]

    func contacts(forTask taskId: UUIDv7) async -> [Contact]
    func taskIds(forContact contactId: UUIDv7) async -> [UUIDv7]
    func addContact(_ contactId: UUIDv7, toTask taskId: UUIDv7) async throws
    func removeContact(_ contactId: UUIDv7, fromTask taskId: UUIDv7) async throws

    /// Merges source contacts into `primary`: unions fields, groups, and task
    /// links, then soft-deletes the sources.
    func merge(_ sourceIds: [UUIDv7], into primary: Contact, at: Date) async throws
}

/// In-memory implementation used by tests and previews.
public actor InMemoryContactRepository: ContactRepository {
    private var items: [UUIDv7: Contact] = [:]
    private var groupItems: [UUIDv7: ContactGroup] = [:]
    private var memberships: [UUIDv7: Set<UUIDv7>] = [:] // contact -> groups
    private var taskLinks: [UUIDv7: Set<UUIDv7>] = [:] // task -> contacts

    public init() {}

    public init(contacts: [Contact], groups: [ContactGroup] = []) {
        for contact in contacts { items[contact.id] = contact }
        for group in groups { groupItems[group.id] = group }
    }

    public func contacts() async -> [Contact] {
        items.values
            .filter { $0.deletedAt == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func contact(_ id: UUIDv7) async -> Contact? {
        guard let item = items[id], item.deletedAt == nil else { return nil }
        return item
    }

    public func save(_ contact: Contact) async throws {
        items[contact.id] = contact
    }

    public func delete(_ id: UUIDv7, at: Date) async throws {
        guard var item = items[id] else { return }
        item.deletedAt = at
        item.updatedAt = at
        item.version += 1
        items[id] = item
        memberships[id] = nil
        for task in taskLinks.keys {
            taskLinks[task]?.remove(id)
        }
    }

    public func groups() async -> [ContactGroup] {
        groupItems.values.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    public func saveGroup(_ group: ContactGroup) async throws {
        groupItems[group.id] = group
    }

    public func deleteGroup(_ id: UUIDv7) async throws {
        groupItems[id] = nil
        for contact in memberships.keys {
            memberships[contact]?.remove(id)
        }
    }

    public func groupIds(for contactId: UUIDv7) async -> [UUIDv7] {
        Array(memberships[contactId] ?? []).sorted { $0.uuid.uuidString < $1.uuid.uuidString }
    }

    public func setGroups(_ groupIds: [UUIDv7], for contactId: UUIDv7) async throws {
        memberships[contactId] = Set(groupIds)
    }

    public func contacts(inGroup groupId: UUIDv7) async -> [Contact] {
        let ids = memberships.filter { $0.value.contains(groupId) }.map(\.key)
        return items.values
            .filter { ids.contains($0.id) && $0.deletedAt == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func contacts(forTask taskId: UUIDv7) async -> [Contact] {
        let ids = taskLinks[taskId] ?? []
        return items.values
            .filter { ids.contains($0.id) && $0.deletedAt == nil }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func taskIds(forContact contactId: UUIDv7) async -> [UUIDv7] {
        taskLinks.filter { $0.value.contains(contactId) }.map(\.key)
    }

    public func addContact(_ contactId: UUIDv7, toTask taskId: UUIDv7) async throws {
        taskLinks[taskId, default: []].insert(contactId)
    }

    public func removeContact(_ contactId: UUIDv7, fromTask taskId: UUIDv7) async throws {
        taskLinks[taskId]?.remove(contactId)
    }

    public func merge(_ sourceIds: [UUIDv7], into primary: Contact, at: Date) async throws {
        var merged = primary
        for id in sourceIds where id != primary.id {
            guard let source = items[id] else { continue }
            merged = ContactMerger.merge([merged, source], primary: merged, at: at)
            memberships[primary.id, default: []].formUnion(memberships[id] ?? [])
            for task in taskLinks.keys {
                if taskLinks[task]?.contains(id) == true {
                    taskLinks[task]?.insert(primary.id)
                    taskLinks[task]?.remove(id)
                }
            }
            try await delete(id, at: at)
        }
        items[primary.id] = merged
    }
}
