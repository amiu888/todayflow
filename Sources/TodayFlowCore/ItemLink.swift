import Foundation

/// A directed relationship between two work items (driver.md §2, §11).
///
/// Semantics of `.blocks`: `fromId` is a *prerequisite* of `toId`. `toId` is the
/// blocked (locked) item — it cannot complete until `fromId` is done. Dragging A onto
/// B with "Before" creates `blocks(A → B)`: B is locked until A completes.
///
/// `.blocks` links must form a forest (no cycles): a link that would create a cycle is
/// rejected (driver.md §11: "would create a loop").
public struct ItemLink: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
        /// `fromId` must complete before `toId`; `toId` is the blocked one.
        case blocks
        /// A soft "related to" association; carries no ordering or lock.
        case relatesTo
    }

    public var id: UUIDv7
    /// The prerequisite item (for `.blocks`) or the source of the association.
    public var fromId: UUIDv7
    /// The dependent / blocked item (for `.blocks`).
    public var toId: UUIDv7
    public var kind: Kind
    // Sync-ready conventions (driver.md §6).
    public var createdAt: Date
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        fromId: UUIDv7,
        toId: UUIDv7,
        kind: Kind = .blocks,
        createdAt: Date = .now,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.fromId = fromId
        self.toId = toId
        self.kind = kind
        self.createdAt = createdAt
        self.version = version
        self.deviceId = deviceId
    }
}
