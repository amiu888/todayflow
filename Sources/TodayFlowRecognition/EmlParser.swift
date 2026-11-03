import Foundation

/// The parsed contents of an RFC 822 (`.eml`) message.
public struct EmlMessage: Hashable, Sendable {
    public var subject: String?
    public var from: String?
    public var to: String?
    public var date: Date?
    public var messageId: String?
    public var body: String?

    public init(
        subject: String? = nil,
        from: String? = nil,
        to: String? = nil,
        date: Date? = nil,
        messageId: String? = nil,
        body: String? = nil
    ) {
        self.subject = subject
        self.from = from
        self.to = to
        self.date = date
        self.messageId = messageId
        self.body = body
    }
}

/// A small, pure RFC 822 message parser (driver.md §7: recognizers are pure and
/// unit-tested with fixtures, so the parser lives here, not in the app target).
///
/// Handles what the recognizers need: header unfolding, RFC 2047 encoded words
/// in header values, a few common `Date` formats, and the body.
public enum EmlParser {
    public static func parse(_ data: Data) -> EmlMessage {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(text)
    }

    public static func parse(_ raw: String) -> EmlMessage {
        let lines = unfold(raw).components(separatedBy: "\n")

        // The header section ends at the first blank line.
        var headerCount = lines.count
        for (index, line) in lines.enumerated()
        where line.trimmingCharacters(in: .whitespaces) == "" {
            headerCount = index
            break
        }

        var headers: [String: String] = [:]
        for line in lines.prefix(headerCount) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { continue }
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Keep the first occurrence of each header.
            if headers[name] == nil {
                headers[name] = decodeEncodedWords(value)
            }
        }

        let body = lines
            .dropFirst(headerCount + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)

        return EmlMessage(
            subject: headers["subject"],
            from: headers["from"],
            to: headers["to"],
            date: headers["date"].flatMap(parseDate),
            messageId: headers["message-id"],
            body: body.isEmpty ? nil : body
        )
    }

    // MARK: - Header unfolding

    /// Reassembles continuation lines (those starting with space or tab) into the
    /// previous line, per RFC 822 §1.1.
    static func unfold(_ text: String) -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
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

    // MARK: - RFC 2047 encoded words

    /// Decodes `=?charset?Q?...?=` / `=?charset?B?...?=` words in a header value.
    static func decodeEncodedWords(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "=\\?([^?]+)\\?([QqBb])\\?([^?]*)\\?="
        ) else {
            return value
        }

        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        guard !matches.isEmpty else { return value }

        // Rebuild the string from the original text, word by word. The
        // whitespace between two adjacent encoded words is not part of the
        // value (RFC 2047 §6.2: "=?a?Q?x?= =?b?Q?y?=" → "xy"); any other
        // text between words is kept.
        var result = ""
        var cursor = value.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: value),
                  fullRange.lowerBound >= cursor else { continue }

            let gap = value[cursor..<fullRange.lowerBound]
            if gap.trimmingCharacters(in: .whitespaces) != "" {
                result += gap
            }

            guard
                let charsetRange = Range(match.range(at: 1), in: value),
                let encodingRange = Range(match.range(at: 2), in: value),
                let textRange = Range(match.range(at: 3), in: value)
            else {
                result += value[fullRange]
                cursor = fullRange.upperBound
                continue
            }

            let charset = String(value[charsetRange])
            let encoding = value[encodingRange].uppercased()
            let text = String(value[textRange])

            let decoded: String?
            if encoding == "Q" {
                decoded = decodeQ(text, charset: charset)
            } else {
                let cleaned = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                decoded = Data(base64Encoded: cleaned).flatMap { String(data: $0, encoding: Self.encoding(for: charset)) }
            }
            result += decoded ?? String(value[fullRange])
            cursor = fullRange.upperBound
        }
        result += value[cursor...]
        return result
    }

    /// Decodes a Q-encoded word: `_` is a space, `=XX` is a byte, everything
    /// else is literal. The byte sequence is decoded with the declared charset.
    static func decodeQ(_ text: String, charset: String) -> String? {
        let encoding = Self.encoding(for: charset)
        var bytes = [UInt8]()
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "_" {
                bytes.append(0x20)
                index = text.index(after: index)
            } else if character == "=" {
                // A `=XX` pair is a byte escape; anything else is a literal `=`.
                let next = text.index(after: index)
                if next < text.endIndex {
                    var hexEnd = next
                    var digits = ""
                    for _ in 0..<2 where hexEnd < text.endIndex {
                        digits.append(text[hexEnd])
                        hexEnd = text.index(after: hexEnd)
                    }
                    if digits.count == 2, let value = UInt8(digits, radix: 16) {
                        bytes.append(value)
                        index = hexEnd
                    } else {
                        bytes.append(0x3D)
                        index = next
                    }
                } else {
                    bytes.append(0x3D)
                    index = next
                }
            } else {
                bytes.append(contentsOf: String(character).data(using: encoding) ?? Data([0x3F]))
                index = text.index(after: index)
            }
        }
        return String(bytes: bytes, encoding: encoding)
    }

    static func encoding(for charset: String) -> String.Encoding {
        switch charset.lowercased() {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1", "latin-1", "8859-1": return .isoLatin1
        case "us-ascii", "ascii": return .ascii
        case "windows-1252", "cp1252", "cp 1252": return .windowsCP1252
        default: return .utf8
        }
    }

    // MARK: - Date

    /// Parses the common RFC 822 date shapes.
    static func parseDate(_ value: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss ZZZ",
            "EEE, dd MMM yy HH:mm:ss ZZZ",
            "EEE dd MMM yyyy HH:mm:ss",
            "dd MMM yyyy HH:mm:ss",
            "dd MMM yy HH:mm:ss",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}
