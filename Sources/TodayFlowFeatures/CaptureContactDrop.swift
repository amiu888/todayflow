import Foundation
import TodayFlowCore

/// One contact object inside the capture sheet. The user can opt out of adding
/// it and choose a group. A contact with no match is added as a new contact;
/// one that matches an existing contact waits for the user's choice
/// (Keep Both, Replace, Merge or Use Existing) in the compare window.
public struct CaptureContactDrop: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var imported: ImportedContact
    public var addToContacts: Bool
    public var groupId: UUIDv7?
    public var match: ContactMatch?
    public var choice: ContactDropChoice?

    public init(
        id: UUID = UUID(),
        imported: ImportedContact,
        addToContacts: Bool = true,
        groupId: UUIDv7? = nil,
        match: ContactMatch? = nil,
        choice: ContactDropChoice? = nil
    ) {
        self.id = id
        self.imported = imported
        self.addToContacts = addToContacts
        self.groupId = groupId
        self.match = match
        self.choice = choice
    }

    /// The existing contact this one matches, if any.
    public var duplicate: Contact? { match?.existing }

    /// Matches an existing contact and the user hasn't said what to do yet.
    public var needsChoice: Bool { addToContacts && match != nil && choice == nil }
}
