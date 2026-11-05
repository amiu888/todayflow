import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// Recognizes a contact dragged from macOS Contacts or Outlook: a vCard file,
/// vCard pasteboard data, or a contact text card.
public struct ContactRecognizer: ObjectRecognizer {
    public init() {}

    public func canHandle(_ object: DroppedObject) -> Bool {
        if let file = object.fileURL {
            let ext = file.pathExtension.lowercased()
            if ext == "vcf" || ext == "vcard" { return true }
        }
        if object.uti?.conforms(to: .vCard) == true { return true }
        if let text = object.text {
            if text.contains("BEGIN:VCARD") { return true }
            let source = (object.sourceApp ?? "").lowercased()
            if source.contains("contacts") || source.contains("addressbook") {
                return text.contains("@") || text.contains(where: \.isNumber)
            }
        }
        return false
    }

    public func recognize(_ object: DroppedObject) -> RecognizedObject {
        let source = object.sourceApp ?? "contacts"
        var contact: ImportedContact?
        if let text = object.text, text.contains("BEGIN:VCARD") {
            contact = VCardParser.parse(text, source: source).first
        } else if let data = object.fileData,
                  let text = String(data: data, encoding: .utf8),
                  text.contains("BEGIN:VCARD")
        {
            contact = VCardParser.parse(text, source: source).first
        } else if let text = object.text {
            contact = ContactTextParser.parse(text, source: source)
        }

        guard let contact else {
            return RecognizedObject(
                type: .contact,
                displayName: object.fileURL?.lastPathComponent ?? "Contact",
                sourceApp: source,
                reference: object.fileURL?.path
            )
        }

        let details = [
            contact.company,
            contact.jobTitle,
            contact.emails.joined(separator: ", "),
            contact.phones.joined(separator: ", "),
            contact.notes,
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        return RecognizedObject(
            type: .contact,
            uti: object.uti?.identifier ?? "public.vcard",
            displayName: contact.displayName,
            sourceApp: source,
            reference: contact.emails.first ?? contact.phones.first,
            metadata: [
                "contact.company": contact.company,
                "contact.emails": contact.emails.joined(separator: "\n"),
                "contact.phones": contact.phones.joined(separator: "\n"),
            ],
            suggestedTitle: "Follow up with \(contact.displayName)",
            previewText: details,
            contact: contact
        )
    }
}
