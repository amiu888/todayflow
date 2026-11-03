import Foundation

/// A discrete, checkable step within a work item (driver.md §2).
///
/// Action items are the "to-dos" inside a task's detail view. They are ordered by
/// `sortOrder` (a plain integer — action lists are short, so fractional indexing is
/// not needed here) and contribute to the parent's progress roll-up.
public struct ActionItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUIDv7
    /// The work item this action belongs to.
    public var itemId: UUIDv7
    public var text: String
    public var isDone: Bool
    /// Display order within the parent's action list.
    public var sortOrder: Int
    // Sync-ready conventions (driver.md §6).
    public var createdAt: Date
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        itemId: UUIDv7,
        text: String,
        isDone: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.itemId = itemId
        self.text = text
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.version = version
        self.deviceId = deviceId
    }
}
