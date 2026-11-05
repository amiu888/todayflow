#if canImport(AppKit)
import AppKit
import Contacts
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Imports contacts from macOS Contacts and from vCard/CSV files exported by
/// Outlook, Apple Contacts, Google Contacts, and other address books.
@MainActor
public final class ContactsImporter {
    public init() {}

    public var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    public func requestAccess() async -> Bool {
        let store = CNContactStore()
        return await withCheckedContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Reads the user's macOS Contacts, including group names.
    public func importFromContacts() throws -> [ImportedContact] {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var groupNamesByIdentifier: [String: [String]] = [:]
        if let groups = try? store.groups(matching: nil) {
            for group in groups {
                let predicate = CNContact.predicateForContactsInGroup(
                    withIdentifier: group.identifier
                )
                if let members = try? store.unifiedContacts(
                    matching: predicate,
                    keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]
                ) {
                    for member in members {
                        groupNamesByIdentifier[member.identifier, default: []]
                            .append(group.name)
                    }
                }
            }
        }

        var results: [ImportedContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            let emails = contact.emailAddresses.map { $0.value as String }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            // Notes require Apple's restricted contacts-notes entitlement;
            // omit the key rather than failing the whole fetch.
            let notes = ""
            guard !emails.isEmpty || !phones.isEmpty
                || !contact.givenName.isEmpty || !contact.familyName.isEmpty
            else { return }
            results.append(ImportedContact(
                firstName: contact.givenName,
                lastName: contact.familyName,
                company: contact.organizationName,
                jobTitle: contact.jobTitle,
                emails: emails,
                phones: phones,
                notes: notes,
                groupNames: groupNamesByIdentifier[contact.identifier] ?? [],
                source: "macos",
                externalId: contact.identifier
            ))
        }
        return results
    }

    /// Reads a `.vcf`/`.vcard`/`.csv` file exported from Outlook or another
    /// address book.
    public func importFile(at url: URL) throws -> [ImportedContact] {
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        switch url.pathExtension.lowercased() {
        case "vcf", "vcard", "contact":
            return VCardParser.parse(text, source: "outlook")
        case "csv":
            return CSVContactParser.parse(text, source: "outlook")
        case "tsv":
            return CSVContactParser.parse(text, source: "outlook", delimiter: "\t")
        default:
            let vcards = VCardParser.parse(text, source: "vcard")
            return vcards.isEmpty
                ? CSVContactParser.parse(text, source: "csv")
                : vcards
        }
    }

    /// NSOpenPanel configured for contact file imports.
    public func chooseImportFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Contacts"
        panel.message = "Choose a vCard (.vcf) or CSV file exported from Outlook, Contacts, or another address book."
        panel.prompt = "Import"
        panel.allowedContentTypes = [
            .commaSeparatedText,
            UTType(filenameExtension: "vcf") ?? .data,
            UTType(filenameExtension: "vcard") ?? .data,
            .tabSeparatedText,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
#endif
