import Foundation

/// Finds the to-dos in a message without AI: list lines ("- ", "• ", "1. ",
/// "[ ]") and sentences that ask for something ("can you…", "please…",
/// "don't forget to…"). Used when Apple Intelligence isn't available, and
/// to clean up what the model returns.
public enum TodoExtractor {
    /// The most to-dos one suggestion offers.
    public static let limit = 8

    public static func todos(in text: String) -> [String] {
        var found: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let item = listItem(line) {
                found.append(item)
                continue
            }
            for sentence in sentences(line) {
                if let ask = request(sentence) { found.append(ask) }
            }
        }
        return clean(found)
    }

    /// Trims, drops empty and repeated items (ignoring case), keeps at most
    /// `limit`, and leaves out the ones in `existing`.
    public static func clean(_ todos: [String], existing: [String] = []) -> [String] {
        var seen = Set(existing.map(key))
        var result: [String] = []
        for todo in todos {
            var text = todo.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "-•*·")))
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasSuffix(".") { text.removeLast() }
            guard text.count >= 3, text.count <= 140 else { continue }
            text = text.prefix(1).uppercased() + text.dropFirst()
            guard seen.insert(key(text)).inserted else { continue }
            result.append(text)
            if result.count == limit { break }
        }
        return result
    }

    // MARK: - Rules

    private static let bullets = ["- ", "• ", "* ", "· ", "– ", "[ ] ", "[] ", "☐ ", "□ "]

    private static func listItem(_ line: String) -> String? {
        for bullet in bullets where line.hasPrefix(bullet) {
            return String(line.dropFirst(bullet.count))
        }
        // "1. Book flights" or "2) Send the deck"
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") { return String(rest.dropFirst(2)) }
        }
        return nil
    }

    private static let asks: [(prefix: String, keep: Bool)] = [
        ("can you please ", false), ("could you please ", false), ("can you ", false), ("could you ", false),
        ("would you ", false), ("please ", false), ("pls ", false), ("don't forget to ", false),
        ("dont forget to ", false), ("remember to ", false), ("make sure to ", false), ("make sure you ", false),
        ("we need to ", false), ("i need you to ", false), ("you need to ", false), ("need to ", false),
        ("todo: ", false), ("to do: ", false), ("action: ", false),
    ]

    /// Words people put before an ask: "Also please…", "Hey, can you…".
    private static let leadIns = ["also ", "and ", "oh and ", "ok ", "okay ", "hey ", "hi ", "btw ", "so ", "then "]

    private static func request(_ sentence: String) -> String? {
        var sentence = withoutSender(sentence)
        var trimmed = true
        while trimmed {
            trimmed = false
            let lower = sentence.lowercased()
            for leadIn in leadIns where lower.hasPrefix(leadIn) {
                sentence = String(sentence.dropFirst(leadIn.count)).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                trimmed = true
                break
            }
        }
        let lower = sentence.lowercased()
        for ask in asks {
            if let range = lower.range(of: ask.prefix), range.lowerBound == lower.startIndex
                || lower[..<range.lowerBound].hasSuffix(", ") {
                var rest = String(sentence[range.upperBound...])
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: "?!. "))
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }

    /// "Maria: can you…" or "Mom - please…": a chat line starts with who
    /// wrote it (one to three words).
    private static func withoutSender(_ line: String) -> String {
        for separator in [": ", " - ", " – "] {
            guard let range = line.range(of: separator) else { continue }
            let sender = line[..<range.lowerBound]
            let words = sender.split(separator: " ")
            guard (1...3).contains(words.count), sender.count <= 30,
                  sender.allSatisfy({ $0.isLetter || $0 == " " || $0 == "." || $0 == "'" })
            else { continue }
            return String(line[range.upperBound...])
        }
        return line
    }

    private static func sentences(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in line {
            current.append(character)
            if ".?!".contains(character) {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current.trimmingCharacters(in: .whitespaces))
        }
        return result
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
