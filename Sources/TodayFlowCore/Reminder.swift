import Foundation

/// A scheduled nudge (driver.md §2, §11).
///
/// Two kinds: a reminder about a specific task, and the end-of-day summary. The
/// acceptance criteria (driver.md §11) drive the end-of-day behavior: two tasks still
/// open at 15:00 → a notification with Mark done / Snooze / Move to tomorrow.
public struct Reminder: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
        /// Remind about a specific task (`itemId` is set).
        case task
        /// The end-of-day summary (`itemId` is `nil`).
        case endOfDay
    }

    public var id: UUIDv7
    /// The task this reminder is about, or `nil` for an end-of-day summary.
    public var itemId: UUIDv7?
    public var kind: Kind
    /// When the reminder fires.
    public var fireAt: Date
    /// Set once the reminder has been delivered (so it is not re-fired).
    public var deliveredAt: Date?
    // Sync-ready conventions (driver.md §6).
    public var createdAt: Date
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        itemId: UUIDv7? = nil,
        kind: Kind,
        fireAt: Date,
        deliveredAt: Date? = nil,
        createdAt: Date = .now,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.itemId = itemId
        self.kind = kind
        self.fireAt = fireAt
        self.deliveredAt = deliveredAt
        self.createdAt = createdAt
        self.version = version
        self.deviceId = deviceId
    }

    /// True once the reminder has fired.
    public var isDelivered: Bool { deliveredAt != nil }
}
