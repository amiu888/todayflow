import Foundation
import Testing
import TodayFlowCore

@Suite("Contact file parsers")
struct ContactFileParserTests {
    @Test func parsesVCardFieldsAndGroups() {
        let vcard = """
            BEGIN:VCARD
            VERSION:3.0
            N:Smith;Jane;;;
            FN:Jane Smith
            ORG:Acme;Sales
            TITLE:Buyer
            EMAIL;TYPE=WORK:jane@acme.com
            EMAIL;TYPE=HOME:jane@example.com
            TEL;TYPE=CELL:+1 555 0100
            NOTE:Met at conference\\, follow up
            CATEGORIES:Customers,VIP
            UID:contact-1
            END:VCARD
            """
        let contacts = VCardParser.parse(vcard, source: "outlook")
        #expect(contacts.count == 1)
        let contact = contacts[0]
        #expect(contact.firstName == "Jane")
        #expect(contact.lastName == "Smith")
        #expect(contact.company == "Acme")
        #expect(contact.jobTitle == "Buyer")
        #expect(contact.emails == ["jane@acme.com", "jane@example.com"])
        #expect(contact.phones == ["+1 555 0100"])
        #expect(contact.groupNames == ["Customers", "VIP"])
        #expect(contact.externalId == "contact-1")
    }

    @Test func unfoldsVCardLinesAndDecodesQuotedPrintable() {
        let vcard = """
            BEGIN:VCARD
            VERSION:3.0
            N:Doe;John;;;
            NOTE;ENCODING=QUOTED-PRINTABLE:Hello =E2=9C=93
             continued
            EMAIL:john@example.com
            END:VCARD
            """
        let contact = VCardParser.parse(vcard).first
        #expect(contact?.notes == "Hello ✓continued")
    }

    @Test func parsesOutlookCSVWithMultipleEmailsAndPhones() {
        let csv = """
            First Name,Last Name,Company,Job Title,E-mail Address,E-mail 2 Address,Business Phone,Mobile Phone,Notes,Categories
            John,Doe,Acme,CEO,john@acme.com,jdoe@home.com,555-0100,555-0101,"Met at expo, Tuesday",Vendors
            ,,,,only@email.com,,,,,
            """
        let contacts = CSVContactParser.parse(csv, source: "outlook")
        #expect(contacts.count == 2)
        #expect(contacts[0].firstName == "John")
        #expect(contacts[0].emails.count == 2)
        #expect(contacts[0].phones.count == 2)
        #expect(contacts[0].notes == "Met at expo, Tuesday")
        #expect(contacts[0].groupNames == ["Vendors"])
        #expect(contacts[1].emails == ["only@email.com"])
    }
}

@Suite("Contact import and merge")
struct ContactImportTests {
    private func existing(
        firstName: String = "Alice",
        email: String = "alice@example.com"
    ) -> Contact {
        Contact(firstName: firstName, emails: [email], source: "macos")
    }

    @Test func importMergesMatchingEmailAndFillsMissingFields() {
        let importer = ContactImporter()
        let plan = importer.plan(
            importing: [
                ImportedContact(
                    firstName: "Alice",
                    lastName: "Ng",
                    company: "Acme",
                    emails: ["ALICE@example.com"],
                    phones: ["+1 555 0100"],
                    source: "outlook"
                )
            ],
            existing: [existing()],
            filter: ContactImportFilter()
        )

        #expect(plan.importedCount == 0)
        #expect(plan.mergedCount == 1)
        #expect(plan.contacts.count == 1)
        #expect(plan.contacts[0].lastName == "Ng")
        #expect(plan.contacts[0].company == "Acme")
        #expect(plan.contacts[0].phones == ["+1 555 0100"])
    }

    @Test func importFilterSkipsRecordsWithoutEmail() {
        let importer = ContactImporter()
        let plan = importer.plan(
            importing: [
                ImportedContact(firstName: "No Email", phones: ["555"], source: "csv"),
                ImportedContact(firstName: "Has Email", emails: ["a@b.com"], source: "csv"),
            ],
            existing: [],
            filter: ContactImportFilter(requireEmail: true)
        )
        #expect(plan.importedCount == 1)
        #expect(plan.skippedCount == 1)
        #expect(plan.contacts.first?.firstName == "Has Email")
    }

    @Test func importCreatesNamedGroups() {
        let importer = ContactImporter()
        let plan = importer.plan(
            importing: [
                ImportedContact(
                    firstName: "Jane",
                    emails: ["jane@acme.com"],
                    groupNames: ["Customers"],
                    source: "outlook"
                )
            ],
            existing: [],
            existingGroups: [ContactGroup(name: "Customers")],
            filter: ContactImportFilter()
        )
        #expect(plan.newGroups.isEmpty)
        #expect(plan.groupAssignments.values.first?.count == 1)
    }

    @Test func deduplicatorGroupsByEmailAndPhone() {
        let contacts = [
            Contact(firstName: "Alice", emails: ["a@example.com"]),
            Contact(firstName: "Alicia", emails: ["A@example.com"]),
            Contact(firstName: "Bob", phones: ["+1 (555) 0100"]),
            Contact(firstName: "Robert", phones: ["15550100"]),
            Contact(firstName: "Carol", emails: ["carol@example.com"]),
        ]
        let groups = ContactDeduplicator.duplicateGroups(in: contacts)
        #expect(groups.count == 2)
        #expect(groups.contains { $0.count == 2 })
    }

    @Test func mergerUnionsEmailsPhonesAndNotes() {
        let primary = Contact(firstName: "Alice", emails: ["a@example.com"], notes: "First")
        let other = Contact(firstName: "Alice", emails: ["b@example.com"], phones: ["555"], notes: "Second")
        let merged = ContactMerger.merge([primary, other], primary: primary)
        #expect(merged.emails == ["a@example.com", "b@example.com"])
        #expect(merged.phones == ["555"])
        #expect(merged.notes.contains("First"))
        #expect(merged.notes.contains("Second"))
    }
}

@Suite("Contact parser edge cases")
struct ContactParserEdgeCaseTests {
    @Test func vCardNoteIsDecoded() {
        let vcard = """
            BEGIN:VCARD
            N:Smith;Jane;;;
            EMAIL:jane@acme.com
            NOTE:Met at conference\\, follow up
            END:VCARD
            """
        #expect(VCardParser.parse(vcard).first?.notes == "Met at conference, follow up")
    }

    @Test func vCardEscapedBackslashIsNotADecodedNewline() {
        let vcard = "BEGIN:VCARD\nN:Doe;Jane;;;\nNOTE:literal \\\\n\nEMAIL:jane@acme.com\nEND:VCARD"
        #expect(VCardParser.parse(vcard).first?.notes == "literal \\n")
    }

    @Test func csvSupportsQuotedNewlines() {
        let csv = """
            First Name,Notes
            Jane,"line one
            line two"
            """
        #expect(CSVContactParser.parse(csv).first?.notes == "line one\nline two")
    }

    @Test func csvSupportsTabs() {
        let tsv = "First Name\tE-mail Address\nJane\tjane@acme.com"
        let contact = CSVContactParser.parse(tsv, delimiter: "\t").first
        #expect(contact?.firstName == "Jane")
        #expect(contact?.emails == ["jane@acme.com"])
    }

    @Test func importFilterMatchesFreeText() {
        let record = ImportedContact(
            firstName: "Jane",
            company: "Acme",
            emails: ["jane@acme.com"],
            groupNames: ["Customers"],
            source: "csv"
        )
        #expect(ContactImportFilter(query: "acme").matches(record))
        #expect(ContactImportFilter(query: "customers").matches(record))
        #expect(!ContactImportFilter(query: "beta").matches(record))
    }

    @Test func importedContactTrimsDeduplicatesAndSortsFields() {
        let record = ImportedContact(
            firstName: "  Jane ",
            emails: [" b@acme.com ", "a@acme.com", "a@acme.com"],
            phones: [" 555 ", "555", " 666 "],
            source: "csv"
        )
        let contact = record.contact(deviceId: "test", at: .now)
        #expect(contact.firstName == "Jane")
        #expect(contact.emails == ["a@acme.com", "b@acme.com"])
        #expect(contact.phones == ["555", "666"])
    }
}

@Test func importedGroupsSortAfterExistingGroups() {
    let existing = ContactGroup(name: "Existing", sortOrder: "0002")
    let plan = ContactImporter().plan(
        importing: [
            ImportedContact(
                firstName: "Jane",
                emails: ["jane@acme.com"],
                groupNames: ["New group"],
                source: "csv"
            )
        ],
        existing: [],
        existingGroups: [existing]
    )
    let newGroup = plan.newGroups.first
    #expect(newGroup != nil)
    #expect(FractionalIndex.isLessThan("0002", newGroup!.sortOrder))
}
