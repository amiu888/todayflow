import Foundation

/// Import filtering: free-text search plus minimum contactability.
public struct ContactImportFilter: Hashable, Sendable {
    public var query: String
    public var requireEmail: Bool
    public var requirePhone: Bool

    public init(query: String = "", requireEmail: Bool = false, requirePhone: Bool = false) {
        self.query = query
        self.requireEmail = requireEmail
        self.requirePhone = requirePhone
    }

    public func matches(_ record: ImportedContact) -> Bool {
        if requireEmail, record.emails.isEmpty { return false }
        if requirePhone, record.phones.isEmpty { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return true }
        let haystack = (
            [record.firstName, record.lastName, record.company, record.jobTitle, record.notes]
                + record.emails + record.phones + record.groupNames
        ).joined(separator: " ").lowercased()
        return haystack.contains(trimmed)
    }
}

/// A preview of what an import will do. Saving is the caller's job so the UI
/// can show the count before committing.
public struct ContactImportPlan: Sendable {
    public var contacts: [Contact]
    public var newGroups: [ContactGroup]
    /// Contact id -> group ids that should be attached after saving.
    public var groupAssignments: [UUIDv7: [UUIDv7]]
    public var importedCount: Int
    public var mergedCount: Int
    public var skippedCount: Int

    public init(
        contacts: [Contact] = [],
        newGroups: [ContactGroup] = [],
        groupAssignments: [UUIDv7: [UUIDv7]] = [:],
        importedCount: Int = 0,
        mergedCount: Int = 0,
        skippedCount: Int = 0
    ) {
        self.contacts = contacts
        self.newGroups = newGroups
        self.groupAssignments = groupAssignments
        self.importedCount = importedCount
        self.mergedCount = mergedCount
        self.skippedCount = skippedCount
    }
}

/// Turns imported records into new/updated contacts, matching by external id,
/// normalized email, or normalized phone. Matches are merged in place.
public struct ContactImporter: Sendable {
    public init() {}

    public func plan(
        importing records: [ImportedContact],
        existing: [Contact],
        existingGroups: [ContactGroup] = [],
        filter: ContactImportFilter = ContactImportFilter(),
        deviceId: String = "local",
        now: Date = .now
    ) -> ContactImportPlan {
        var working = existing
        var groupByName: [String: ContactGroup] = [:]
        for group in existingGroups {
            groupByName[group.name.lowercased()] = group
        }
        var lastGroupOrder = existingGroups.map(\.sortOrder)
            .max(by: FractionalIndex.isLessThan)
        var newGroups: [ContactGroup] = []
        var assignments: [UUIDv7: Set<UUIDv7>] = [:]
        var touched: Set<UUIDv7> = []
        var imported = 0
        var merged = 0
        var skipped = 0

        func groupID(named name: String) -> UUIDv7? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            if let existing = groupByName[key] { return existing.id }
            let order = FractionalIndex.midpoint(lastGroupOrder, nil)
            lastGroupOrder = order
            let group = ContactGroup(
                name: trimmed,
                sortOrder: order,
                createdAt: now,
                updatedAt: now,
                deviceId: deviceId
            )
            groupByName[key] = group
            newGroups.append(group)
            return group.id
        }

        for record in records {
            guard filter.matches(record) else {
                skipped += 1
                continue
            }
            let incoming = record.contact(deviceId: deviceId, at: now)
            let matchIndex = working.firstIndex { existingContact in
                if let externalId = record.externalId,
                   let existingExternal = existingContact.externalId,
                   externalId == existingExternal,
                   record.source == existingContact.source
                {
                    return true
                }
                return !Set(existingContact.canonicalEmails)
                    .isDisjoint(with: incoming.canonicalEmails)
                    || !Set(existingContact.canonicalPhones)
                    .isDisjoint(with: incoming.canonicalPhones)
            }

            let contact: Contact
            if let matchIndex {
                contact = ContactMerger.merge(
                    [working[matchIndex], incoming],
                    primary: working[matchIndex],
                    at: now
                )
                working[matchIndex] = contact
                merged += 1
            } else {
                working.append(incoming)
                contact = incoming
                imported += 1
            }
            touched.insert(contact.id)
            for name in record.groupNames {
                if let id = groupID(named: name) {
                    assignments[contact.id, default: []].insert(id)
                }
            }
        }

        let contacts = working.filter { touched.contains($0.id) }
        return ContactImportPlan(
            contacts: contacts,
            newGroups: newGroups,
            groupAssignments: assignments.mapValues { Array($0) },
            importedCount: imported,
            mergedCount: merged,
            skippedCount: skipped
        )
    }
}

/// Combines contacts without losing emails, phones, notes, or source ids.
public enum ContactMerger {
    public static func merge(
        _ contacts: [Contact],
        primary: Contact,
        at now: Date = .now
    ) -> Contact {
        var result = primary
        for other in contacts where other.id != primary.id {
            if result.firstName.isEmpty { result.firstName = other.firstName }
            if result.lastName.isEmpty { result.lastName = other.lastName }
            if result.company.isEmpty { result.company = other.company }
            if result.jobTitle.isEmpty { result.jobTitle = other.jobTitle }
            if result.externalId == nil { result.externalId = other.externalId }
            if result.source == "manual" { result.source = other.source }

            result.emails = mergeUnique(result.emails, other.emails) {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            result.phones = mergeUnique(result.phones, other.phones) {
                $0.filter(\.isNumber)
            }
            if !other.notes.isEmpty, !result.notes.contains(other.notes) {
                result.notes = [result.notes, other.notes]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
            }
        }
        result.updatedAt = now
        result.version += 1
        return result
    }

    private static func mergeUnique(
        _ first: [String],
        _ second: [String],
        key: (String) -> String
    ) -> [String] {
        var seen = Set(first.map(key))
        var result = first
        for value in second {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let valueKey = key(trimmed)
            guard !valueKey.isEmpty, seen.insert(valueKey).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}

/// Finds groups of contacts that share an email or phone number.
public enum ContactDeduplicator {
    public static func duplicateGroups(in contacts: [Contact]) -> [[Contact]] {
        let active = contacts.filter { $0.deletedAt == nil }
        var parent = Array(0..<active.count)
        func find(_ index: Int) -> Int {
            var index = index
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        var emailOwner: [String: Int] = [:]
        var phoneOwner: [String: Int] = [:]
        for (index, contact) in active.enumerated() {
            for email in contact.canonicalEmails {
                if let owner = emailOwner[email] { union(index, owner) }
                else { emailOwner[email] = index }
            }
            for phone in contact.canonicalPhones {
                if let owner = phoneOwner[phone] { union(index, owner) }
                else { phoneOwner[phone] = index }
            }
        }

        var groups: [Int: [Contact]] = [:]
        for (index, contact) in active.enumerated() {
            groups[find(index), default: []].append(contact)
        }
        return groups.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.displayName ?? "") < ($1.first?.displayName ?? "") }
    }
}

public extension Contact {
    var canonicalEmails: [String] {
        emails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    var canonicalPhones: [String] {
        phones.map { $0.filter(\.isNumber) }.filter { !$0.isEmpty }
    }
}

public extension ImportedContact {
    func contact(deviceId: String, at now: Date) -> Contact {
        Contact(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            company: company.trimmingCharacters(in: .whitespacesAndNewlines),
            jobTitle: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            emails: Array(Set(emails.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted(),
            phones: Array(Set(phones.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted(),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source,
            externalId: externalId,
            createdAt: now,
            updatedAt: now,
            deviceId: deviceId
        )
    }
}
