import Foundation

/// Keys for `RecognizedObject.metadata` / `Attachment.metadata` (driver.md §7).
///
/// The metadata map is `[String: String]`, so dates are carried as ISO-8601
/// strings (see `Iso8601`) and sizes as decimal strings.
public enum MetadataKeys {
    public static let from = "from"
    public static let to = "to"
    public static let receivedAt = "receivedAt"
    public static let messageId = "messageId"
    public static let startAt = "startAt"
    public static let endAt = "endAt"
    public static let location = "location"
    public static let organizer = "organizer"
    public static let joinLink = "joinLink"
    public static let path = "path"
    public static let size = "size"
    public static let domain = "domain"
    public static let link = "link"
    public static let sender = "sender"
    public static let officeKind = "officeKind"
    public static let pageCount = "pageCount"
    public static let pageTitle = "pageTitle"
    public static let dimensions = "dimensions"
    public static let jiraIssueKey = "jiraIssueKey"
    public static let jiraProjectKey = "jiraProjectKey"
    public static let jiraSummary = "jiraSummary"
    public static let jiraURL = "jiraURL"
}

/// ISO-8601 formatting for the string-typed metadata values.
///
/// `ISO8601DateFormatter` is a class and not `Sendable`, so it lives in an
/// immutable `@unchecked Sendable` box (the formatter is never mutated after
/// creation).
public enum Iso8601 {
    private final class Box: @unchecked Sendable {
        let formatter: ISO8601DateFormatter
        init() {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            self.formatter = formatter
        }
    }

    private static let box = Box()

    public static func encode(_ date: Date) -> String {
        box.formatter.string(from: date)
    }

    public static func decode(_ string: String) -> Date? {
        box.formatter.date(from: string)
    }
}
