import Foundation

/// The parsed contents of a `VEVENT` in an iCalendar (`.ics`) file.
public struct IcsEvent: Hashable, Sendable {
    public var summary: String?
    public var start: Date?
    public var end: Date?
    public var location: String?
    /// The organizer's email address (the `mailto:` part of `ORGANIZER`).
    public var organizer: String?
    /// The organizer's display name (`CN` parameter), when present.
    public var organizerName: String?
    /// The event's join link (`URL` property).
    public var url: String?

    public init(
        summary: String? = nil,
        start: Date? = nil,
        end: Date? = nil,
        location: String? = nil,
        organizer: String? = nil,
        organizerName: String? = nil,
        url: String? = nil
    ) {
        self.summary = summary
        self.start = start
        self.end = end
        self.location = location
        self.organizer = organizer
        self.organizerName = organizerName
        self.url = url
    }
}

/// A small, pure iCalendar parser (driver.md §7: recognizers are pure and
/// unit-tested with fixtures).
///
/// Handles line unfolding, the first `VEVENT` block, and the properties the
/// recognizers need: `SUMMARY`, `DTSTART`, `DTEND`, `LOCATION`, `ORGANIZER`,
/// `URL`. Date-times are parsed by hand (`YYYYMMDD[THHMMSS][Z]`) rather than
/// with `DateFormatter`, because iCalendar's format is fixed-width.
public enum IcsParser {
    public static func parse(_ data: Data) -> IcsEvent? {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(text)
    }

    public static func parse(_ raw: String) -> IcsEvent? {
        let lines = unfold(raw).components(separatedBy: "\r\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var inEvent = false
        var event = IcsEvent()
        for line in lines {
            guard !line.isEmpty else { continue }
            if line.hasPrefix("BEGIN:VEVENT") {
                inEvent = true
                continue
            }
            if line.hasPrefix("END:VEVENT") {
                break
            }
            guard inEvent else { continue }
            parseProperty(line, into: &event)
        }

        // An event with no summary and no dates is not useful.
        guard event.summary != nil || event.start != nil else { return nil }
        return event
    }

    // MARK: - Properties

    private static func parseProperty(_ line: String, into event: inout IcsEvent) {
        // NAME;PARAM=VALUE;PARAM2=VALUE2:value
        guard let colon = line.firstIndex(of: ":") else { return }
        let namePart = line[..<colon]
        let value = line[line.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)

        var name = ""
        var parameters: [String: String] = [:]
        for component in namePart.components(separatedBy: ";") {
            if let equals = component.firstIndex(of: "=") {
                let key = component[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
                let value = component[component.index(after: equals)...]
                    .trimmingCharacters(in: .whitespaces)
                parameters[key] = value
            } else {
                name = component.trimmingCharacters(in: .whitespaces).uppercased()
            }
        }

        switch name {
        case "SUMMARY":
            event.summary = value.isEmpty ? nil : value
        case "DTSTART":
            event.start = parseDateTime(value, parameters: parameters)
        case "DTEND":
            event.end = parseDateTime(value, parameters: parameters)
        case "LOCATION":
            event.location = value.isEmpty ? nil : value
        case "ORGANIZER":
            event.organizerName = parameters["CN"]
            event.organizer = organizerEmail(from: value)
        case "URL":
            event.url = value.isEmpty ? nil : value
        default:
            break
        }
    }

    /// Parses `YYYYMMDD[THHMMSS][Z]` with `TZID` / `VALUE=DATE` parameters.
    static func parseDateTime(_ value: String, parameters: [String: String]) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let isDateOnly = parameters["VALUE"]?.uppercased() == "DATE" || trimmed.count == 8
        let hasZulu = trimmed.hasSuffix("Z")
        var digits = trimmed.hasSuffix("Z") ? String(trimmed.dropLast()) : trimmed
        // The `T` date/time separator is not part of the digit run.
        digits = digits.replacingOccurrences(of: "T", with: "")

        var timeZone: TimeZone
        if let tzid = parameters["TZID"], let named = TimeZone(identifier: tzid) {
            timeZone = named
        } else if hasZulu {
            timeZone = TimeZone(identifier: "UTC")!
        } else {
            timeZone = .current
        }

        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.timeZone = timeZone

        guard digits.count == 8 || digits.count == 12 || digits.count == 14,
              digits.allSatisfy(\.isNumber)
        else { return nil }

        components.year = Int(digits.prefix(4))
        components.month = Int(digits.dropFirst(4).prefix(2))
        components.day = Int(digits.dropFirst(6).prefix(2))
        if digits.count >= 12 {
            components.hour = Int(digits.dropFirst(8).prefix(2))
            components.minute = Int(digits.dropFirst(10).prefix(2))
        }
        if digits.count >= 14 {
            components.second = Int(digits.dropFirst(12).prefix(2))
        }
        if isDateOnly, digits.count == 8 {
            components.hour = nil
            components.minute = nil
            components.second = nil
        }
        return calendar.date(from: components)
    }

    /// Extracts the email from an `ORGANIZER` value (`mailto:` or bare address).
    static func organizerEmail(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let mailto = trimmed.range(of: "mailto:", options: .caseInsensitive) else {
            return trimmed.contains("@") ? trimmed : nil
        }
        let address = trimmed[mailto.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        // Cut off any `?params` suffix.
        let question = address.firstIndex(of: "?")
        let email = question.map { String(address[..<$0]) } ?? address
        return email.isEmpty ? nil : email
    }

    // MARK: - Line unfolding

    /// Reassembles continuation lines (those starting with space or tab) into
    /// the previous line, per RFC 5545 §3.1.
    static func unfold(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                let continuation = line.dropFirst().description
                if let last = lines.indices.last {
                    lines[last] += continuation
                } else {
                    lines.append(continuation)
                }
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }
}
