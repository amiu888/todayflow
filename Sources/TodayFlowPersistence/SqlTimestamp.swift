import Foundation

/// ISO-8601 UTC encoding for the `*_at` TEXT columns (driver.md §6 sync-ready convention).
///
/// Timestamps are stored as UTC strings with millisecond precision, e.g.
/// `2026-01-05T09:30:00.123Z`. That keeps the columns human-readable in the raw
/// database, and — because every value shares one fixed-width format — lexicographic
/// comparison in SQL is the same as chronological comparison.
public enum SqlTimestamp {
    /// `ISO8601DateFormatter` is neither thread-safe nor `Sendable`, so the two
    /// formatters live in a single `@unchecked Sendable` box together with the
    /// lock that guards every access. The box is immutable after `init`, and
    /// `encode`/`decode` are the only entry points — both lock.
    private final class Formatters: @unchecked Sendable {
        let lock = NSLock()
        let fractional: ISO8601DateFormatter
        let plain: ISO8601DateFormatter

        init() {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            f.timeZone = TimeZone(identifier: "UTC")! // contract: UTC, never local
            fractional = f

            let p = ISO8601DateFormatter()
            p.formatOptions = [.withInternetDateTime]
            p.timeZone = TimeZone(identifier: "UTC")!
            plain = p
        }
    }

    private static let formatters = Formatters()

    /// Encodes a `Date` as an ISO-8601 UTC string with millisecond precision.
    public static func encode(_ date: Date) -> String {
        let f = formatters
        f.lock.lock()
        defer { f.lock.unlock() }
        return f.fractional.string(from: date)
    }

    /// Decodes an ISO-8601 UTC string, with or without fractional seconds.
    /// Returns `nil` for unparseable input.
    public static func decode(_ string: String) -> Date? {
        let f = formatters
        f.lock.lock()
        defer { f.lock.unlock() }
        return f.fractional.date(from: string) ?? f.plain.date(from: string)
    }
}
