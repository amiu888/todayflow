import Foundation

/// Why a dropped contact looks like one already in Contacts.
public struct ContactMatch: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case sameSource
        case email(String)
        case phone(String)
    }

    public var existing: Contact
    public var reason: Reason

    public init(existing: Contact, reason: Reason) {
        self.existing = existing
        self.reason = reason
    }

    /// "Same email: jane@acme.com".
    public var explanation: String {
        switch reason {
        case .sameSource: return "Same contact from the same app"
        case .email(let email): return "Same email: \(email)"
        case .phone(let phone): return "Same phone: \(phone)"
        }
    }
}

/// Finds the contact a dropped record most likely duplicates.
public enum ContactMatcher {
    /// Shorter numbers (extensions, "0") match too many people to count.
    public static let minimumPhoneDigits = 7

    public static func match(for record: ImportedContact, in existing: [Contact]) -> ContactMatch? {
        let active = existing.filter { $0.deletedAt == nil }
        if let externalId = record.externalId, !externalId.isEmpty,
           let same = active.first(where: { $0.externalId == externalId && $0.source == record.source })
        {
            return ContactMatch(existing: same, reason: .sameSource)
        }
        let emails = Set(record.canonicalEmails)
        for contact in active {
            if let email = contact.emails.first(where: { emails.contains(Self.emailKey($0)) }) {
                return ContactMatch(existing: contact, reason: .email(email))
            }
        }
        let phones = Set(record.canonicalPhones.filter { $0.count >= minimumPhoneDigits })
        for contact in active {
            if let phone = contact.phones.first(where: { phones.contains(Self.phoneKey($0)) }) {
                return ContactMatch(existing: contact, reason: .phone(phone))
            }
        }
        return nil
    }

    static func emailKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func phoneKey(_ value: String) -> String {
        value.filter(\.isNumber)
    }
}

/// The side-by-side merge: for each field the user keeps the value in
/// Contacts (left) or the dropped one (right); emails and phones from both
/// sides can each be kept or dropped.
public struct ContactMergeDraft: Hashable, Sendable {
    public enum Side: Hashable, Sendable { case existing, dropped }

    public enum Field: String, CaseIterable, Hashable, Sendable, Identifiable {
        case firstName, lastName, company, jobTitle, notes
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .firstName: return "First name"
            case .lastName: return "Last name"
            case .company: return "Company"
            case .jobTitle: return "Job title"
            case .notes: return "Notes"
            }
        }
    }

    public struct Value: Hashable, Sendable, Identifiable {
        public var id: String { "\(side == .existing ? "L" : "R")|\(text)" }
        public var text: String
        public var side: Side
        public var kept: Bool
    }

    public let existing: Contact
    public let dropped: Contact
    public var choices: [Field: Side]
    public var emails: [Value]
    public var phones: [Value]

    public init(existing: Contact, dropped: Contact) {
        self.existing = existing
        self.dropped = dropped
        var choices: [Field: Side] = [:]
        for field in Field.allCases {
            let left = Self.value(field, of: existing)
            let right = Self.value(field, of: dropped)
            choices[field] = left.isEmpty && !right.isEmpty ? .dropped : .existing
        }
        self.choices = choices
        self.emails = Self.values(existing.emails, dropped.emails, key: ContactMatcher.emailKey)
        self.phones = Self.values(existing.phones, dropped.phones, key: ContactMatcher.phoneKey)
    }

    public static func value(_ field: Field, of contact: Contact) -> String {
        switch field {
        case .firstName: return contact.firstName
        case .lastName: return contact.lastName
        case .company: return contact.company
        case .jobTitle: return contact.jobTitle
        case .notes: return contact.notes
        }
    }

    /// Fields where the two sides differ and both have something.
    public var conflicts: [Field] {
        Field.allCases.filter { isConflict($0) }
    }

    public func isConflict(_ field: Field) -> Bool {
        let left = Self.value(field, of: existing).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = Self.value(field, of: dropped).trimmingCharacters(in: .whitespacesAndNewlines)
        return !left.isEmpty && !right.isEmpty && left != right
    }

    /// True when both sides have the same value (or the dropped one is empty).
    public func isSame(_ field: Field) -> Bool {
        let left = Self.value(field, of: existing).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = Self.value(field, of: dropped).trimmingCharacters(in: .whitespacesAndNewlines)
        return left == right
    }

    /// The merged contact: the existing row (same id, groups and task links)
    /// with the chosen values.
    public func merged(at now: Date) -> Contact {
        var result = existing
        for field in Field.allCases {
            let source = choices[field] == .dropped ? dropped : existing
            let value = Self.value(field, of: source)
            switch field {
            case .firstName: result.firstName = value
            case .lastName: result.lastName = value
            case .company: result.company = value
            case .jobTitle: result.jobTitle = value
            case .notes: result.notes = value
            }
        }
        result.emails = emails.filter(\.kept).map(\.text)
        result.phones = phones.filter(\.kept).map(\.text)
        if result.externalId == nil { result.externalId = dropped.externalId }
        return result.touching(now)
    }

    /// The existing row with every field from the dropped contact. Groups and
    /// task links stay, because the id stays.
    public func replaced(at now: Date) -> Contact {
        var result = existing
        result.firstName = dropped.firstName
        result.lastName = dropped.lastName
        result.company = dropped.company
        result.jobTitle = dropped.jobTitle
        result.notes = dropped.notes
        result.emails = dropped.emails
        result.phones = dropped.phones
        result.source = dropped.source
        result.externalId = dropped.externalId
        return result.touching(now)
    }

    private static func values(_ left: [String], _ right: [String], key: (String) -> String) -> [Value] {
        var seen = Set<String>()
        var result: [Value] = []
        for (list, side) in [(left, Side.existing), (right, Side.dropped)] {
            for raw in list {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let valueKey = key(text)
                guard !text.isEmpty, !valueKey.isEmpty, seen.insert(valueKey).inserted else { continue }
                result.append(Value(text: text, side: side, kept: true))
            }
        }
        return result
    }
}

/// What to do with a dropped contact that matches one in Contacts.
public enum ContactDropChoice: Hashable, Sendable {
    /// Add the dropped contact as a second, separate contact.
    case keepBoth
    /// Overwrite the existing contact with the dropped details.
    case replace
    /// Keep the values picked in the side-by-side merge.
    case merge(ContactMergeDraft)
    /// Link the existing contact and change nothing.
    case useExisting

    public var label: String {
        switch self {
        case .keepBoth: return "Keep both"
        case .replace: return "Replace"
        case .merge: return "Merge"
        case .useExisting: return "Use existing"
        }
    }

    public var logName: String {
        switch self {
        case .keepBoth: return "keepBoth"
        case .replace: return "replace"
        case .merge: return "merge"
        case .useExisting: return "useExisting"
        }
    }

    /// The contact to save (nil for `useExisting`) for the dropped one.
    public func contactToSave(existing: Contact, dropped: Contact, at now: Date) -> Contact? {
        switch self {
        case .keepBoth:
            var separate = dropped
            separate.source = "drag"
            separate.externalId = nil
            return separate
        case .replace:
            return ContactMergeDraft(existing: existing, dropped: dropped).replaced(at: now)
        case .merge(let draft):
            return draft.merged(at: now)
        case .useExisting:
            return nil
        }
    }
}
