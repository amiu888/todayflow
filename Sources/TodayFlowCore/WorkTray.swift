import Foundation

/// A named staging tray for tasks the user is actively working on
/// (the “office tray” metaphor). Trays are lightweight views over existing
/// tasks: membership does not change a task's day or status.
public struct WorkTray: Identifiable, Hashable, Codable, Sendable {
    public var id: UUIDv7
    public var name: String
    public var itemIds: [UUIDv7]
    /// Left-to-right order in the tray strip.
    public var sortOrder: Int
    /// Hex color chosen by the user; missing in older saved trays.
    public var colorHex: String?

    public init(
        id: UUIDv7 = .new(),
        name: String,
        itemIds: [UUIDv7] = [],
        sortOrder: Int = 0,
        colorHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.sortOrder = sortOrder
        self.colorHex = colorHex
    }
}
