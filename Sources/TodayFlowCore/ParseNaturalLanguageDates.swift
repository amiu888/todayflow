import Foundation

/// Extracts natural-language date and time expressions from free text
/// (driver.md FR-05): "today 3pm", "tomorrow", "next Friday", "14:30",
/// "in two days".
///
/// Detection is two-pass:
/// 1. `NSDataDetector` (date type) resolves absolute and most relative
///    expressions ("3pm", "14:30", "today 3pm", "tomorrow", "next Friday",
///    "in 3 days", "tonight", "this afternoon"). In the current SDK the date
///    type covers time and date detection; there is no separate time or
///    relative type. The detector cannot be pinned to a locale or an "as of"
///    date — it resolves against the real current date in the current locale.
/// 2. A small regex fallback covers what the detector misses: word-numeral
///    relatives ("in two days") and "midnight" / "noon".
///
/// Pure and synchronous: the capture sheet re-runs this on every keystroke of
/// the title and description, so it must be cheap and side-effect free.
/// Resolution defaults (business start, end-of-business) come from the
/// injected `WorkCalendar`.
public struct ParseNaturalLanguageDates: Sendable {
    /// One extracted date expression and its resolved instants.
    public struct ParsedDate: Hashable, Sendable {
        /// The matched text, e.g. "today 3pm".
        public var text: String
        /// Resolved start: the matched instant, or the business start of a
        /// date-only match.
        public var start: Date
        /// Resolved end (due time): end-of-business on the start's day,
        /// clamped to at least the start (an 18:00 start keeps 18:00 as its
        /// due time).
        public var end: Date
    }

    /// Calendar for all date math (time zone, weekday layout).
    public let calendar: Calendar
    /// Working-hours model for business-start / end-of-business defaults.
    public let workCalendar: WorkCalendar

    public init(
        calendar: Calendar = .current,
        workCalendar: WorkCalendar = .standard
    ) {
        self.calendar = calendar
        self.workCalendar = workCalendar
    }

    /// Returns all date expressions found in `text`, in order of appearance.
    /// `now` anchors the roll-forward of past times and the fallback
    /// resolution of relative expressions; the detector itself always
    /// resolves against the real current date.
    /// Text without a recognizable date expression returns an empty array.
    public func parse(_ text: String, at now: Date) -> [ParsedDate] {
        let hits = collectHits(in: text, at: now)
            .sorted { $0.location < $1.location }

        // Pair a date-only hit with a time-only hit that follows it closely,
        // because "today, 3pm" may arrive as two separate matches.
        var pairedTime = [Int: Int]()
        var consumedTime = Set<Int>()
        for (i, hit) in hits.enumerated() where hit.hasDay && !hit.hasTime {
            for (j, candidate) in hits.enumerated()
            where !consumedTime.contains(j)
                && candidate.hasTime && !candidate.hasDay
                && candidate.location >= hit.location + hit.length
                && candidate.location - (hit.location + hit.length) <= 6
            {
                pairedTime[i] = j
                consumedTime.insert(j)
                break
            }
        }

        var results: [ParsedDate] = []
        for (i, hit) in hits.enumerated() where !consumedTime.contains(i) {
            let pairedTimeHit = pairedTime[i].map { hits[$0] }
            let start = resolveStart(for: hit, at: now, pairedTimeHit: pairedTimeHit)
            let end = max(workCalendar.endOfBusiness(for: start), start)
            results.append(ParsedDate(text: hit.text, start: start, end: end))
        }
        return results
    }

    // MARK: - Hit collection

    private struct Hit {
        let location: Int
        let length: Int
        let text: String
        let hasDay: Bool
        let hasTime: Bool
        let instant: Date
    }

    /// Only the date type is used: in the current SDK it covers time and
    /// relative detection, and `NSDataDetector` throws an uncatchable ObjC
    /// exception for any other (unverified) mask bits.
    ///
    /// `nonisolated(unsafe)` on the detector and the regex caches below:
    /// they are immutable after init and thread-safe for `matches()`, which
    /// the compiler cannot verify for these Foundation classes.
    nonisolated(unsafe) static let detector: NSDataDetector? =
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Time expressions: "3pm", "3 pm", "14:30", "tonight", "afternoon", …
    /// Case-insensitive: "3PM" and "Tonight" classify the same way.
    nonisolated(unsafe) static let timeExpr = try! NSRegularExpression(
        pattern: "\\b(\\d{1,2}:\\d{2}|\\d{1,2}\\s?[ap]m|midnight|noon|tonight|morning|afternoon|evening)\\b",
        options: [.caseInsensitive]
    )

    /// Day expressions: day names, month names, today/tomorrow, ISO dates,
    /// and relative phrases ("in two days"). Case-insensitive: "Friday".
    nonisolated(unsafe) static let dayExpr = try! NSRegularExpression(
        pattern: "\\b(today|tomorrow|tonight|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|in\\s+(a|an|one|two|three|four|five|six|seven|eight|nine|ten|\\d+)\\s+(minutes?|hours?|days?|weeks?|months?)|\\d{4}-\\d{2}-\\d{2})\\b",
        options: [.caseInsensitive]
    )

    /// Relative phrases the detector misses (word numerals: "in two days").
    nonisolated(unsafe) static let relativeExpr = try! NSRegularExpression(
        pattern: "\\b(in|within)\\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an|\\d+)\\s+(minutes?|hours?|days?|weeks?|months?)\\b",
        options: [.caseInsensitive]
    )

    /// "midnight" / "noon" — the detector does not match either.
    nonisolated(unsafe) static let midnightNoonExpr = try! NSRegularExpression(
        pattern: "\\b(midnight|noon)\\b",
        options: [.caseInsensitive]
    )

    private static let wordNumbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "a": 1, "an": 1
    ]

    private func collectHits(in text: String, at now: Date) -> [Hit] {
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var hits: [Hit] = []

        if let detector = Self.detector {
            for match in detector.matches(in: text, options: [], range: fullRange) {
                guard let instant = match.date,
                      let range = Range(match.range, in: text)
                else { continue }
                let hitText = String(text[range])
                let hitFull = NSRange(hitText.startIndex..<hitText.endIndex, in: hitText)
                // The detector's result type is always `.date` and its
                // components come back nil, so day/time is classified from
                // the matched text itself.
                let hasTime = !Self.timeExpr.matches(in: hitText, options: [], range: hitFull).isEmpty
                let hasDay = !Self.dayExpr.matches(in: hitText, options: [], range: hitFull).isEmpty
                guard hasDay || hasTime else { continue }
                hits.append(Hit(
                    location: match.range.location,
                    length: match.range.length,
                    text: hitText,
                    hasDay: hasDay,
                    hasTime: hasTime,
                    instant: instant
                ))
            }
        }

        // Fallback pass: expressions the detector misses. Skips ranges that
        // overlap an existing hit.
        for m in Self.relativeExpr.matches(in: text, options: [], range: fullRange) {
            guard let range = Range(m.range, in: text),
                  let valueRange = Range(m.range(at: 2), in: text),
                  let unitRange = Range(m.range(at: 3), in: text),
                  !overlaps(hits, m.range)
            else { continue }
            let value = Int(text[valueRange].lowercased())
                ?? Self.wordNumbers[text[valueRange].lowercased()] ?? 1
            let unitText = text[unitRange].lowercased()
            let unit: Calendar.Component = unitText.hasPrefix("minute") ? .minute
                : unitText.hasPrefix("hour") ? .hour
                : unitText.hasPrefix("day") ? .day
                : unitText.hasPrefix("week") ? .weekOfYear
                : .month
            let instant = calendar.date(byAdding: unit, value: value, to: now) ?? now
            let hasTime = unit == .minute || unit == .hour
            hits.append(Hit(
                location: m.range.location,
                length: m.range.length,
                text: String(text[range]),
                hasDay: !hasTime,
                hasTime: hasTime,
                instant: instant
            ))
        }

        for m in Self.midnightNoonExpr.matches(in: text, options: [], range: fullRange) {
            guard let range = Range(m.range, in: text),
                  !overlaps(hits, m.range)
            else { continue }
            let isMidnight = text[range].lowercased() == "midnight"
            let instant = calendar.date(
                bySettingHour: isMidnight ? 0 : 12, minute: 0, second: 0, of: now
            ) ?? now
            hits.append(Hit(
                location: m.range.location,
                length: m.range.length,
                text: String(text[range]),
                hasDay: false,
                hasTime: true,
                instant: instant
            ))
        }

        return hits
    }

    private func overlaps(_ hits: [Hit], _ range: NSRange) -> Bool {
        hits.contains {
            $0.location < range.location + range.length
                && range.location < $0.location + $0.length
        }
    }

    // MARK: - Resolution

    private func resolveStart(for hit: Hit, at now: Date, pairedTimeHit: Hit?) -> Date {
        if hit.hasDay && hit.hasTime {
            // One match carrying both ("today 3pm", "tonight").
            return hit.instant
        }
        if hit.hasDay {
            if let pairedTimeHit {
                // Date + a separately matched time ("today" + "3pm").
                let hour = calendar.component(.hour, from: pairedTimeHit.instant)
                let minute = calendar.component(.minute, from: pairedTimeHit.instant)
                return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: hit.instant)
                    ?? hit.instant
            }
            // Date-only ("tomorrow"): start of business on that day.
            return workCalendar.startOfBusiness(for: hit.instant)
        }
        // Time-only ("3pm"): the detector does not roll past times forward,
        // so if the instant is already in the past, roll forward a day —
        // the same after-hours convention as `WorkCalendar.defaultEndAt`.
        var start = hit.instant
        if start < now {
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return start
    }
}
