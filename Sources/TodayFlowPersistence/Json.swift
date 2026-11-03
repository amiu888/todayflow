import Foundation

/// JSON helpers for the `*_json` TEXT columns and the `change_outbox` payload.
///
/// `JSONEncoder`/`JSONDecoder` are reference types that are **not** `Sendable`, so
/// under Swift 6 strict concurrency they cannot be shared `static let` singletons.
/// Encoding is cheap and writes are infrequent, so each call builds a fresh instance.
///
/// Dates are encoded/decoded as the same ISO-8601 UTC strings used by the `*_at`
/// columns (`SqlTimestamp`), keeping the outbox payload byte-compatible with the
/// rest of the database (driver.md §6 sync-ready convention).
public enum Json {
    /// Encodes `value` to a UTF-8 JSON string. Dates use `SqlTimestamp` (ISO-8601 UTC).
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, container in
            // The closure receives an existential `Encoder`, whose generic
            // `encode` cannot be called directly — route through a single-value
            // container, whose `encode(String)` is non-generic (but mutating).
            var single = container.singleValueContainer()
            try single.encode(SqlTimestamp.encode(date))
        }
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    /// Decodes `T` from a UTF-8 JSON string. Dates use `SqlTimestamp`.
    public static func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            // The closure receives an existential `Decoder`; route through a
            // single-value container to read the date string. (`Decoder
            // .singleValueContainer()` is `throws` in this SDK.)
            let single = try container.singleValueContainer()
            let s = try single.decode(String.self)
            guard let date = SqlTimestamp.decode(s) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "Bad date string: \(s)"
                    )
                )
            }
            return date
        }
        return try decoder.decode(type, from: Data(string.utf8))
    }

    // MARK: - Tolerant string/array/object helpers (for the `*_json` columns)

    /// Encodes a string array, or `"[]"` if it fails.
    public static func arrayString(_ values: [String]) -> String {
        (try? encode(values)) ?? "[]"
    }

    /// Decodes a string array, or `[]` if the input is missing/malformed.
    public static func array(from string: String) -> [String] {
        (try? decode([String].self, from: string)) ?? []
    }

    /// Encodes a string dictionary, or `"{}"` if it fails.
    public static func objectString(_ values: [String: String]) -> String {
        (try? encode(values)) ?? "{}"
    }

    /// Decodes a string dictionary, or `[:]` if the input is missing/malformed.
    public static func object(from string: String) -> [String: String] {
        (try? decode([String: String].self, from: string)) ?? [:]
    }
}
