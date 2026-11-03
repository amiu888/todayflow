import Foundation

/// A UUIDv7 (RFC 9562) identifier.
///
/// UUIDv7 packs a 48-bit millisecond timestamp into the most-significant bits, so
/// identifiers sort by creation time. We use it for every persisted entity
/// (driver.md §6) so rows order chronologically and sync merges are unambiguous.
///
/// Layout (16 bytes):
/// ```
/// | 48-bit unix ms | 4-bit ver(7) | 12-bit rand | 2-bit var(10) | 62-bit rand |
/// ```
public struct UUIDv7: Hashable, Sendable, CustomStringConvertible, Comparable, Codable {
    public let uuid: UUID

    public init(_ uuid: UUID) {
        self.uuid = uuid
    }

    public var description: String { uuid.uuidString }

    /// Create a new UUIDv7 stamped with the current system clock.
    public static func new() -> UUIDv7 {
        UUIDv7(timestampMilliseconds: Int64(Date.now.timeIntervalSince1970 * 1000))
    }

    /// Create a UUIDv7 with an explicit millisecond timestamp (deterministic in tests).
    public init(timestampMilliseconds: Int64) {
        var bytes = [UInt8](repeating: 0, count: 16)
        let ts = UInt64(max(0, timestampMilliseconds))
        // 48-bit timestamp, big-endian, into bytes 0–5.
        bytes[0] = UInt8((ts >> 40) & 0xFF)
        bytes[1] = UInt8((ts >> 32) & 0xFF)
        bytes[2] = UInt8((ts >> 24) & 0xFF)
        bytes[3] = UInt8((ts >> 16) & 0xFF)
        bytes[4] = UInt8((ts >> 8) & 0xFF)
        bytes[5] = UInt8(ts & 0xFF)
        // Byte 6: version 7 in the high nibble, random in the low nibble.
        var rng = SystemRandomNumberGenerator()
        bytes[6] = (UInt8.random(in: 0...255, using: &rng) & 0x0F) | 0x70
        bytes[7] = UInt8.random(in: 0...255, using: &rng)
        // Byte 8: variant 10 in the top two bits, random in the low six.
        bytes[8] = (UInt8.random(in: 0...255, using: &rng) & 0x3F) | 0x80
        for i in 9...15 {
            bytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        self.uuid = UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
        )
    }

    /// Read the 48-bit creation timestamp (unix milliseconds) back out of the UUID.
    public var timestampMilliseconds: Int64 {
        let b = uuid.uuid
        let v = (UInt64(b.0) << 40)
            | (UInt64(b.1) << 32)
            | (UInt64(b.2) << 24)
            | (UInt64(b.3) << 16)
            | (UInt64(b.4) << 8)
            | UInt64(b.5)
        return Int64(v)
    }

    /// The creation instant as a `Date`.
    public var timestamp: Date {
        Date(timeIntervalSince1970: TimeInterval(timestampMilliseconds) / 1000)
    }

    /// Order by the raw 16 bytes, so creation-time order is preserved.
    ///
    /// The canonical hex string is fixed-width (36 chars, uppercase), so lexicographic
    /// comparison of the strings is exactly byte-wise comparison of the UUIDs.
    public static func < (lhs: UUIDv7, rhs: UUIDv7) -> Bool {
        lhs.uuid.uuidString < rhs.uuid.uuidString
    }

    // MARK: Codable (encode as the canonical string form)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let s = try container.decode(String.self)
        guard let uuid = UUID(uuidString: s) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UUID string: \(s)"
            )
        }
        self.uuid = uuid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid.uuidString)
    }
}
