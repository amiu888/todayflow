import Foundation

/// The parsed contents of an Outlook `.msg` (OLE compound file) message.
public struct MsgMessage: Hashable, Sendable {
    public var subject: String?
    public var sender: String?
    public var body: String?
    /// The delivery time (`PR_MESSAGE_DELIVERY_TIME`).
    public var deliveredAt: Date?
    public var messageId: String?

    public init(
        subject: String? = nil,
        sender: String? = nil,
        body: String? = nil,
        deliveredAt: Date? = nil,
        messageId: String? = nil
    ) {
        self.subject = subject
        self.sender = sender
        self.body = body
        self.deliveredAt = deliveredAt
        self.messageId = messageId
    }
}

/// Reads the message properties out of an Outlook `.msg` file (driver.md §7).
///
/// A `.msg` file is a CFB container whose message fields are `__substg1.0_…`
/// streams directly under the root. The property ID and encoding are encoded
/// in the stream name: `__substg1.0_<propID><type>`, e.g. `0037001F` is the
/// subject as an 8-bit string.
public enum MsgReader {
    /// Reads a `.msg` file. Returns `nil` when the data is not a valid CFB
    /// container or none of the message streams are present.
    public static func read(_ data: Data) -> MsgMessage? {
        guard let cfb = CfbReader(data: data) else { return nil }

        let subject = stringStream(cfb, property: "0037")
        let sender = stringStream(cfb, property: "0065")
        let body = stringStream(cfb, property: "007D")
        let messageId = stringStream(cfb, property: "0077")
        let deliveredAt = timeStream(cfb, property: "0076")

        guard subject != nil || sender != nil || body != nil || deliveredAt != nil else {
            return nil
        }
        return MsgMessage(
            subject: subject,
            sender: sender,
            body: body,
            deliveredAt: deliveredAt,
            messageId: messageId
        )
    }

    /// Reads a string property, trying the 8-bit (`001F`) then 16-bit (`001E`)
    /// stream variant.
    private static func stringStream(_ cfb: CfbReader, property: String) -> String? {
        if let data = cfb.stream(named: "__substg1.0_\(property)001F") {
            return decodeString8(data)
        }
        if let data = cfb.stream(named: "__substg1.0_\(property)001E") {
            return decodeString16(data)
        }
        return nil
    }

    /// Reads an 8-byte `FILETIME` property (`0040`) as a `Date`.
    private static func timeStream(_ cfb: CfbReader, property: String) -> Date? {
        guard let data = cfb.stream(named: "__substg1.0_\(property)0040"),
              data.count >= 8
        else { return nil }
        let ticks = Int64(littleEndian: data.loadInt64(at: 0))
        return fileTimeToSeconds(ticks)
    }

    /// Converts a `FILETIME` (100-ns ticks since 1601-01-01) to a `Date`.
    ///
    /// There are 10,000,000 such ticks in a second, and 11,644,473,600 seconds
    /// between 1601-01-01 and 1970-01-01.
    static func fileTimeToSeconds(_ ticks: Int64) -> Date? {
        guard ticks > 0 else { return nil }
        let seconds = Double(ticks) / 10_000_000 - 11_644_473_600
        return Date(timeIntervalSince1970: seconds)
    }

    /// Decodes a `001F` (string8) stream: 8-bit bytes, UTF-8 with a Latin-1
    /// fallback, trailing NULs stripped.
    static func decodeString8(_ data: Data) -> String? {
        var bytes = [UInt8](data)
        while let last = bytes.last, last == 0 {
            bytes.removeLast()
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
    }

    /// Decodes a `001E` (string16) stream: little-endian UTF-16, trailing NULs
    /// stripped.
    static func decodeString16(_ data: Data) -> String? {
        var bytes = [UInt8](data)
        while bytes.count >= 2, bytes[bytes.count - 2] == 0, bytes[bytes.count - 1] == 0 {
            bytes.removeLast(2)
        }
        guard !bytes.isEmpty else { return nil }
        return String(bytes: bytes, encoding: .utf16LittleEndian)
    }
}

private extension Data {
    func loadInt64(at offset: Int) -> Int64 {
        let bytes = [UInt8](self)
        guard bytes.count >= offset + 8 else { return 0 }
        var value: Int64 = 0
        for i in 0..<8 {
            value |= Int64(bytes[offset + i]) << (8 * i)
        }
        return value
    }
}
