import Foundation
import TodayFlowCore

/// Parses the text a Contacts app puts on the pasteboard when a contact card is
/// dragged. The usual shape is a name line, an email, and a phone number, but
/// the parser also tolerates labels and extra fields.
public enum ContactTextParser {
    public static func parse(_ text: String, source: String = "contacts") -> ImportedContact? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var emails: [String] = []
        var phones: [String] = []
        var notes: [String] = []
        var name: String?
        var company: String?
        let emailPattern = try? NSRegularExpression(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        )

        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = emailPattern?.firstMatch(in: line, range: range),
               let emailRange = Range(match.range, in: line)
            {
                let email = String(line[emailRange])
                if !emails.contains(email) { emails.append(email) }
                continue
            }
            let digits = line.filter(\.isNumber)
            if digits.count >= 7, line.contains(where: { $0.isNumber }) {
                let phone = line
                if !phones.contains(phone) { phones.append(phone) }
                continue
            }
            if name == nil {
                name = line
            } else if company == nil {
                company = line
            } else {
                notes.append(line)
            }
        }

        guard name != nil || !emails.isEmpty || !phones.isEmpty else { return nil }
        let display = name ?? emails.first ?? phones.first ?? "Contact"
        let parts = display.split(separator: " ")
        let firstName = parts.first.map(String.init) ?? display
        let lastName = parts.dropFirst().joined(separator: " ")
        return ImportedContact(
            firstName: firstName,
            lastName: lastName,
            company: company ?? "",
            emails: emails,
            phones: phones,
            notes: notes.joined(separator: "\n"),
            source: source
        )
    }
}
