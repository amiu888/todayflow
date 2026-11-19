import Foundation
import Hummingbird

/// Any JSON value. Row data passes through the server untouched.
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// One row change. `entity` is the table name, `id` the row's primary key.
/// `changedAt` is when the device made the change (ISO 8601, UTC); the newest
/// change to a row wins.
public struct Change: Codable, Sendable, Equatable {
    public var entity: String
    public var id: String
    /// "upsert" or "delete".
    public var op: String
    public var changedAt: String
    /// The whole row for an upsert; ignored for a delete.
    public var data: JSONValue?

    public init(entity: String, id: String, op: String, changedAt: String, data: JSONValue?) {
        self.entity = entity
        self.id = id
        self.op = op
        self.changedAt = changedAt
        self.data = data
    }
}

/// A change as the server stores it: with its sequence number and author.
public struct StoredChange: Codable, Sendable, Equatable {
    public var seq: Int64
    public var entity: String
    public var id: String
    public var op: String
    public var changedAt: String
    public var data: JSONValue?
    public var deviceId: String
}

public struct PushRequest: Codable, Sendable {
    public var changes: [Change]
    public init(changes: [Change]) { self.changes = changes }
}

public struct PushResult: Codable, Sendable {
    public var entity: String
    public var id: String
    /// "accepted", or "stale" when the server already has a newer change.
    public var status: String
    /// The server's newer copy, sent with a "stale" result.
    public var current: StoredChange?
}

public struct PushResponse: ResponseCodable, Sendable {
    public var results: [PushResult]
}

public struct PullResponse: ResponseCodable, Sendable {
    public var changes: [StoredChange]
    /// Pass as `since` on the next pull.
    public var next: Int64
    /// True when more changes are waiting.
    public var more: Bool
}

public struct PairRequest: Codable, Sendable {
    public var pairingCode: String
    public var deviceName: String
    public init(pairingCode: String, deviceName: String) {
        self.pairingCode = pairingCode
        self.deviceName = deviceName
    }
}

public struct PairResponse: ResponseCodable, Sendable {
    public var deviceId: String
    /// The user this device now belongs to.
    public var userName: String?
    /// Shown once; the server keeps only a hash.
    public var token: String
}

public struct StatusResponse: ResponseCodable, Sendable {
    public var ok: Bool
    public var userId: String
    public var userName: String?
    public var records: Int64
    public var latestSeq: Int64
    public var deviceId: String
}

public struct UserInfo: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var createdAt: String
    public var activeDevices: Int64
    public var records: Int64
}

public struct DeviceInfo: Codable, Sendable, Equatable {
    public var id: String
    /// The owning user's name.
    public var user: String
    public var name: String
    public var createdAt: String
    public var lastSeenAt: String?
    public var revoked: Bool
}

public struct BlobResponse: ResponseCodable, Sendable {
    public var sha256: String
    public var size: Int
    /// False when this user had already stored this file.
    public var created: Bool
}
