import Foundation
import Testing
import TodayFlowCore

@Suite("Contact match and merge")
struct ContactMergeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func matchesBySameEmail_andSaysWhy() throws {
        let jane = Contact(firstName: "Jane", emails: ["Jane@Acme.com"])
        let record = ImportedContact(firstName: "J", emails: ["jane@acme.com "], source: "vcard")
        let match = try #require(ContactMatcher.match(for: record, in: [jane]))
        #expect(match.existing.id == jane.id)
        #expect(match.explanation == "Same email: Jane@Acme.com")
    }

    @Test func aDifferentPerson_isNoMatch() {
        let jane = Contact(firstName: "Jane", emails: ["jane@acme.com"], phones: ["+1 555 0100"])
        let bob = ImportedContact(firstName: "Bob", emails: ["bob@acme.com"], phones: ["+1 555 0199"], source: "vcard")
        #expect(ContactMatcher.match(for: bob, in: [jane]) == nil)
    }

    @Test func shortPhoneNumbers_dontMatch() {
        let jane = Contact(firstName: "Jane", phones: ["x100"])
        let bob = ImportedContact(firstName: "Bob", phones: ["100"], source: "vcard")
        #expect(ContactMatcher.match(for: bob, in: [jane]) == nil)
    }

    @Test func deletedContacts_dontMatch() {
        var jane = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        jane.deletedAt = now
        #expect(ContactMatcher.match(for: ImportedContact(emails: ["jane@acme.com"], source: "vcard"), in: [jane]) == nil)
    }

    @Test func draft_picksTheExistingValue_unlessItIsEmpty() {
        let existing = Contact(firstName: "Jane", company: "", jobTitle: "CTO", emails: ["jane@acme.com"])
        let dropped = Contact(firstName: "Janet", company: "Acme", jobTitle: "", emails: ["JANE@acme.com", "j@home.org"])
        let draft = ContactMergeDraft(existing: existing, dropped: dropped)
        #expect(draft.choices[.firstName] == .existing)
        #expect(draft.choices[.company] == .dropped)
        #expect(draft.choices[.jobTitle] == .existing)
        #expect(draft.conflicts == [.firstName])
        // The same email (any case) shows once.
        #expect(draft.emails.map(\.text) == ["jane@acme.com", "j@home.org"])
    }

    @Test func merged_usesThePicks_andKeepsTheId() {
        let existing = Contact(firstName: "Jane", emails: ["jane@acme.com"], phones: ["+1 555 0100"])
        let dropped = Contact(firstName: "Janet", emails: ["j@home.org"])
        var draft = ContactMergeDraft(existing: existing, dropped: dropped)
        draft.choices[.firstName] = .dropped
        draft.emails[0].kept = false

        let merged = draft.merged(at: now)
        #expect(merged.id == existing.id)
        #expect(merged.firstName == "Janet")
        #expect(merged.emails == ["j@home.org"])
        #expect(merged.phones == ["+1 555 0100"])
        #expect(merged.version == existing.version + 1)
    }

    @Test func replaced_takesEverythingFromTheDrop_butKeepsTheId() {
        let existing = Contact(firstName: "Jane", company: "Old", emails: ["jane@acme.com"], notes: "old note")
        let dropped = Contact(firstName: "Jane", company: "New", emails: ["jane@new.com"], source: "outlook")
        let replaced = ContactMergeDraft(existing: existing, dropped: dropped).replaced(at: now)
        #expect(replaced.id == existing.id)
        #expect(replaced.company == "New")
        #expect(replaced.emails == ["jane@new.com"])
        #expect(replaced.notes == "")
        #expect(replaced.source == "outlook")
    }

    @Test func keepBoth_makesASeparateContact() throws {
        let existing = Contact(firstName: "Jane", emails: ["jane@acme.com"])
        let dropped = Contact(firstName: "Jane", emails: ["jane@acme.com"], externalId: "x")
        let saved = try #require(ContactDropChoice.keepBoth.contactToSave(existing: existing, dropped: dropped, at: now))
        #expect(saved.id != existing.id)
        #expect(saved.externalId == nil)
        #expect(ContactDropChoice.useExisting.contactToSave(existing: existing, dropped: dropped, at: now) == nil)
    }
}
