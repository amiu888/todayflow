import Foundation

/// A person or organization the user works with. Contacts are local-first;
/// `source` and `externalId` let imports from macOS Contacts, Outlook files,
/// and vCard/CSV files update the same row instead of duplicating it.
public struct Contact: Identifiable, Hashable, Sendable, Codable {
    public var id: UUIDv7
    public var firstName: String
    public var lastName: String
    public var company: String
    public var jobTitle: String
    public var emails: [String]
    public var phones: [String]
    public var notes: String
    /// `manual`, `macos`, `outlook`, `vcard`, or `csv`.
    public var source: String
    /// Stable identifier from the source system (for example a CNContact id).
    public var externalId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        firstName: String = "",
        lastName: String = "",
        company: String = "",
        jobTitle: String = "",
        emails: [String] = [],
        phones: [String] = [],
        notes: String = "",
        source: String = "manual",
        externalId: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.jobTitle = jobTitle
        self.emails = emails
        self.phones = phones
        self.notes = notes
        self.source = source
        self.externalId = externalId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.version = version
        self.deviceId = deviceId
    }

    public var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if !company.isEmpty { return company }
        if let email = emails.first, !email.isEmpty { return email }
        if let phone = phones.first, !phone.isEmpty { return phone }
        return "Unnamed contact"
    }

    public var initials: String {
        let parts = [firstName, lastName]
            .compactMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).first }
        if parts.isEmpty { return "?" }
        return String(parts.prefix(2)).uppercased()
    }

    public var searchText: String {
        ([firstName, lastName, company, jobTitle, notes]
            + emails + phones)
            .joined(separator: " ")
            .lowercased()
    }

    public func touching(_ now: Date = .now) -> Contact {
        var copy = self
        copy.version += 1
        copy.updatedAt = now
        return copy
    }
}

/// A user-defined group of contacts (customers, vendors, a project team…).
public struct ContactGroup: Identifiable, Hashable, Sendable, Codable {
    public var id: UUIDv7
    public var name: String
    /// Top-level groups have `nil`; child groups point at a top-level parent.
    /// The UI enforces a maximum depth of two levels.
    public var parentId: UUIDv7?
    public var colorHex: String
    public var sortOrder: String
    public var createdAt: Date
    public var updatedAt: Date
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        name: String,
        parentId: UUIDv7? = nil,
        colorHex: String = "#60A5FA",
        sortOrder: String = FractionalIndex.bottom,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
        self.deviceId = deviceId
    }
}

/// A normalized contact from an import source, before it becomes a Contact.
public struct ImportedContact: Hashable, Sendable, Codable {
    public var firstName: String
    public var lastName: String
    public var company: String
    public var jobTitle: String
    public var emails: [String]
    public var phones: [String]
    public var notes: String
    public var groupNames: [String]
    public var source: String
    public var externalId: String?

    public init(
        firstName: String = "",
        lastName: String = "",
        company: String = "",
        jobTitle: String = "",
        emails: [String] = [],
        phones: [String] = [],
        notes: String = "",
        groupNames: [String] = [],
        source: String,
        externalId: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.jobTitle = jobTitle
        self.emails = emails
        self.phones = phones
        self.notes = notes
        self.groupNames = groupNames
        self.source = source
        self.externalId = externalId
    }

    public var displayName: String {
        let name = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        if !company.isEmpty { return company }
        if let email = emails.first, !email.isEmpty { return email }
        if let phone = phones.first, !phone.isEmpty { return phone }
        return "Unnamed contact"
    }
}
