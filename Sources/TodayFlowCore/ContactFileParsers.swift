import Foundation

/// Minimal vCard 3.0/4.0 reader for contact imports. It accepts files exported
/// by Outlook, Apple Contacts, Google Contacts, and most CRM tools.
public enum VCardParser {
    public static func parse(_ text: String, source: String = "vcard") -> [ImportedContact] {
        let unfolded = unfold(text)
        var results: [ImportedContact] = []
        var block: [String] = []

        for rawLine in unfolded.components(separatedBy: .newlines) {
            let line = rawLine
            let upper = line.trimmingCharacters(in: .whitespaces).uppercased()
            if upper == "BEGIN:VCARD" {
                block = []
            } else if upper == "END:VCARD" {
                if let contact = parseBlock(block, source: source) {
                    results.append(contact)
                }
                block = []
            } else if !block.isEmpty || !line.isEmpty {
                block.append(line)
            }
        }
        return results
    }

    private static func unfold(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func parseBlock(
        _ lines: [String],
        source: String
    ) -> ImportedContact? {
        var firstName = ""
        var lastName = ""
        var fullName = ""
        var company = ""
        var jobTitle = ""
        var emails: [String] = []
        var phones: [String] = []
        var notes = ""
        var groups: [String] = []
        var externalId: String?

        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            var key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            var params = ""
            if let semicolon = key.firstIndex(of: ";") {
                params = String(key[key.index(after: semicolon)...])
                key = String(key[..<semicolon])
            }
            let field = key.split(separator: ".").last.map(String.init)?.uppercased() ?? key.uppercased()
            let decoded = decode(value, quotedPrintable: params.uppercased().contains("QUOTED-PRINTABLE"))

            switch field {
            case "N":
                let parts = decoded.components(separatedBy: ";")
                lastName = parts.indices.contains(0) ? parts[0] : ""
                firstName = parts.indices.contains(1) ? parts[1] : ""
            case "FN":
                fullName = decoded
            case "ORG":
                company = decoded.components(separatedBy: ";").first ?? decoded
            case "TITLE":
                jobTitle = decoded
            case "EMAIL":
                let email = decoded.replacingOccurrences(of: "mailto:", with: "")
                if !email.isEmpty { emails.append(email) }
            case "TEL":
                let phone = decoded.replacingOccurrences(of: "tel:", with: "")
                if !phone.isEmpty { phones.append(phone) }
            case "NOTE":
                notes = decoded
            case "CATEGORIES":
                groups = decoded
                    .components(separatedBy: CharacterSet(charactersIn: ",;"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            case "UID":
                externalId = decoded
            default:
                break
            }
        }

        if firstName.isEmpty, lastName.isEmpty, !fullName.isEmpty {
            firstName = fullName
        }
        if firstName.isEmpty, lastName.isEmpty, emails.isEmpty, phones.isEmpty {
            return nil
        }
        return ImportedContact(
            firstName: firstName,
            lastName: lastName,
            company: company,
            jobTitle: jobTitle,
            emails: emails,
            phones: phones,
            notes: notes,
            groupNames: groups,
            source: source,
            externalId: externalId
        )
    }

    private static func decode(_ value: String, quotedPrintable: Bool) -> String {
        var text = value
        if quotedPrintable {
            text = decodeQuotedPrintable(text)
        }
        return unescape(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One pass, so an escaped backslash followed by `n`, `,`, or `;` is not
    /// interpreted as the escape sequence for the following character.
    private static func unescape(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            guard char == "\\" else {
                result.append(char)
                index = text.index(after: index)
                continue
            }
            let next = text.index(after: index)
            guard next < text.endIndex else {
                result.append(char)
                break
            }
            let escaped = text[next]
            switch escaped {
            case "n", "N": result.append("\n")
            case ",": result.append(",")
            case ";": result.append(";")
            case "\\": result.append("\\")
            default: result.append(escaped)
            }
            index = text.index(after: next)
        }
        return result
    }

    private static func decodeQuotedPrintable(_ text: String) -> String {
        let noSoftBreaks = text
            .replacingOccurrences(of: "=\n", with: "")
            .replacingOccurrences(of: "=\r\n", with: "")
        var bytes: [UInt8] = []
        let chars = Array(noSoftBreaks.utf8)
        var index = 0
        while index < chars.count {
            if chars[index] == 61, index + 2 < chars.count,
               let hi = hexValue(chars[index + 1]),
               let lo = hexValue(chars[index + 2])
            {
                bytes.append(hi << 4 | lo)
                index += 3
            } else {
                bytes.append(chars[index])
                index += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}

/// RFC-4180 CSV reader with Outlook/Google/Apple contact header aliases.
public enum CSVContactParser {
    public static func parse(
        _ text: String,
        source: String = "csv",
        delimiter: Character = ","
    ) -> [ImportedContact] {
        let rows = rows(from: text, delimiter: delimiter)
        guard let header = rows.first, !header.isEmpty else { return [] }
        let keys = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let index: (String...) -> Int? = { aliases in
            for alias in aliases {
                if let i = keys.firstIndex(where: { $0 == alias }) { return i }
            }
            return nil
        }
        let contains: (String...) -> [Int] = { needles in
            keys.indices.filter { i in needles.contains { keys[i].contains($0) } }
        }

        let firstNameIndex = index("first name", "given name", "first")
        let lastNameIndex = index("last name", "surname", "family name", "last")
        let fullNameIndex = index("name", "full name", "display name")
        let companyIndex = index("company", "organization", "organisation")
        let titleIndex = index("job title", "title", "position")
        let notesIndex = index("notes", "note")
        let groupsIndex = index("categories", "groups", "group")
        let externalIndex = index("id", "contact id")
        let emailIndices = contains("email", "e-mail")
        let phoneIndices = contains("phone", "mobile", "telephone", "cell")

        var results: [ImportedContact] = []
        for row in rows.dropFirst() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func value(_ i: Int?) -> String {
                guard let i, row.indices.contains(i) else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var emails = emailIndices.map { value($0) }.filter { !$0.isEmpty }
            var phones = phoneIndices.map { value($0) }.filter { !$0.isEmpty }
            var firstName = value(firstNameIndex)
            let lastName = value(lastNameIndex)
            if firstName.isEmpty, lastName.isEmpty {
                firstName = value(fullNameIndex)
            }
            emails = Array(Set(emails)).sorted()
            phones = Array(Set(phones)).sorted()
            guard !firstName.isEmpty || !lastName.isEmpty || !emails.isEmpty || !phones.isEmpty
            else { continue }

            let groups = value(groupsIndex)
                .components(separatedBy: CharacterSet(charactersIn: ",;|"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            results.append(ImportedContact(
                firstName: firstName,
                lastName: lastName,
                company: value(companyIndex),
                jobTitle: value(titleIndex),
                emails: emails,
                phones: phones,
                notes: value(notesIndex),
                groupNames: groups,
                source: source,
                externalId: value(externalIndex).isEmpty ? nil : value(externalIndex)
            ))
        }
        return results
    }

    /// Splits CSV rows while respecting quoted commas, escaped quotes, and
    /// newlines inside quotes.
    static func rows(from text: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if inQuotes {
                if char == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case delimiter:
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    break
                default:
                    field.append(char)
                }
            }
            index = text.index(after: index)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
