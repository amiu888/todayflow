import Foundation

/// One entry in a task's activity log (driver.md FR-20 "activity log").
///
/// Events are append-only and carry the human-readable summary plus the
/// provenance the user asked for: who did it, when, from which app, and the
/// file path / URL involved. They are recorded by the persistence layer in the
/// same transaction as the change they describe.
public struct ActivityEvent: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        case dropped
        case created
        case edited
        case statusChanged
        case completed
        case reopened
        case priorityChanged
        case scheduled
        case reordered
        case reparented
        case attachmentAdded
        case attachmentRemoved
        case linkAdded
        case linkRemoved
        case deleted
        case aiSuggested
        case other
    }

    public var id: UUIDv7
    /// The item this event belongs to.
    public var itemId: UUIDv7
    public var kind: Kind
    /// Short, user-facing description, e.g. `Completed “Ship the release”`.
    public var summary: String
    /// OS user who performed the action (or `local` when unavailable).
    public var actor: String
    /// Bundle id of the app the object came from, when known.
    public var sourceApp: String?
    /// File path, URL, deep link, or message id of the dropped object.
    public var location: String?
    public var occurredAt: Date
    /// Extra provenance: uti, attachment kind, previous values, drag origin…
    public var metadata: [String: String]
    /// Sync-ready device marker.
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        itemId: UUIDv7,
        kind: Kind,
        summary: String,
        actor: String = ActivityActor.current,
        sourceApp: String? = nil,
        location: String? = nil,
        occurredAt: Date = .now,
        metadata: [String: String] = [:],
        deviceId: String = "local"
    ) {
        self.id = id
        self.itemId = itemId
        self.kind = kind
        self.summary = summary
        self.actor = actor
        self.sourceApp = sourceApp
        self.location = location
        self.occurredAt = occurredAt
        self.metadata = metadata
        self.deviceId = deviceId
    }
}

/// The local user performing actions. The app is single-user today; the field
/// exists so a shared/cloud account can populate it later without a migration.
public enum ActivityActor {
    public static var current: String {
        let name = ProcessInfo.processInfo.userName
        return name.isEmpty ? "local" : name
    }
}

/// Port for reading and appending activity events (driver.md §5).
public protocol ActivityRepository: Sendable {
    func record(_ event: ActivityEvent) async throws
    /// Newest first.
    func events(for itemId: UUIDv7) async -> [ActivityEvent]
    /// Newest first across all items.
    func recent(limit: Int) async -> [ActivityEvent]
}
