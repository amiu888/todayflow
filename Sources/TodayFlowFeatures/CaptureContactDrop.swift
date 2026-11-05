import Foundation
import TodayFlowCore

/// How to handle a dropped contact that already exists in Contacts.
public enum ContactDuplicateResolution: String, CaseIterable, Identifiable, Sendable {
    case merge
    case useExisting
    case keepSeparate

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .merge: return "Merge"
        case .useExisting: return "Use existing"
        case .keepSeparate: return "Keep new"
        }
    }

    public var hint: String {
        switch self {
        case .merge:
            return "Updates the existing contact with these details and links this task."
        case .useExisting:
            return "Links the existing contact without changing it."
        case .keepSeparate:
            return "Adds a second contact that intentionally shares an email or phone."
        }
    }
}

/// One contact object inside the capture sheet. The user can opt out of adding
/// it, choose a group, and resolve a duplicate match.
public struct CaptureContactDrop: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var imported: ImportedContact
    public var addToContacts: Bool
    public var groupId: UUIDv7?
    public var duplicate: Contact?
    public var resolution: ContactDuplicateResolution

    public init(
        id: UUID = UUID(),
        imported: ImportedContact,
        addToContacts: Bool = true,
        groupId: UUIDv7? = nil,
        duplicate: Contact? = nil,
        resolution: ContactDuplicateResolution = .merge
    ) {
        self.id = id
        self.imported = imported
        self.addToContacts = addToContacts
        self.groupId = groupId
        self.duplicate = duplicate
        self.resolution = resolution
    }
}
