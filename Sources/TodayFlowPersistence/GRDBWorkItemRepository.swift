import Foundation
import GRDB
import TodayFlowCore

/// The GRDB adapter for `WorkItemRepository` (driver.md §6, §11).
///
/// Conformance notes:
/// - **`save` writes the model's fields verbatim** — including its `version` and
///   `updatedAt`. Version bumping happens in the use cases (`WorkItem.touching`),
///   which is where driver.md §6's "save = upsert, bumps version" contract lives;
///   the repository just persists what it is given. Every `save` appends an
///   `upsert` outbox row in the same transaction.
/// - **`softDelete` / `move` are idempotent no-ops** on missing or
///   already-deleted rows (a `version = version + 1` bump happens only when the
///   row actually changes). This differs from the in-memory adapter, which
///   re-stamps; both satisfy the use-case contracts.
/// - **v1 search is `LIKE`-based** (case-insensitive substring over title and
///   description, exactly matching the in-memory adapter). The FTS5 table and
///   triggers are built (driver.md §6) for the attachment-name search that
///   lands in a later increment.
public final class GRDBWorkItemRepository: WorkItemRepository, Sendable {
    private let queue: DatabaseQueue
    private let actor: String

    public init(queue: DatabaseQueue, actor: String = ActivityActor.current) {
        self.queue = queue
        self.actor = actor
    }

    // MARK: - Reads (non-throwing per the port contract: nil/empty on failure)

    public func item(_ id: UUIDv7) async -> WorkItem? {
        let item = try? await queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM work_item WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.uuid.uuidString]
            ).map { WorkItemRecord(row: $0).model }
        }
        return item ?? nil
    }

    public func todayItems(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        let dayEnd = SqlTimestamp.encode(calendar.endOfDay(for: day))
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE deleted_at IS NULL
                      AND status NOT IN ('done', 'cancelled')
                      AND start_at < ?
                    ORDER BY display_order
                    """,
                arguments: [dayEnd]
            ).map { WorkItemRecord(row: $0).model }
        }
        return items ?? []
    }

    public func completedToday(on day: Date, calendar: WorkCalendar) async -> [WorkItem] {
        let dayStart = calendar.calendar.startOfDay(for: day)
        guard let dayEnd = calendar.calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE deleted_at IS NULL
                      AND status = 'done'
                      AND COALESCE(completed_at, updated_at) >= ?
                      AND COALESCE(completed_at, updated_at) < ?
                    ORDER BY display_order
                    """,
                arguments: [SqlTimestamp.encode(dayStart), SqlTimestamp.encode(dayEnd)]
            ).map { WorkItemRecord(row: $0).model }
        }
        return items ?? []
    }

    public func children(of parentId: UUIDv7?) async -> [WorkItem] {
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE parent_id IS ? AND deleted_at IS NULL
                    ORDER BY display_order
                    """,
                arguments: [parentId?.uuid.uuidString]
            ).map { WorkItemRecord(row: $0).model }
        }
        return items ?? []
    }

    public func allItems() async -> [WorkItem] {
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE deleted_at IS NULL
                    ORDER BY display_order
                    """
            ).map { WorkItemRecord(row: $0).model }
        }
        return items ?? []
    }

    public func search(_ query: String) async -> [WorkItem] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        // Escape LIKE wildcards so the query is treated literally.
        let escaped = needle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE deleted_at IS NULL
                      AND (title LIKE ? ESCAPE '\\' OR description_md LIKE ? ESCAPE '\\')
                    ORDER BY display_order
                    """,
                arguments: [pattern, pattern]
            ).map { WorkItemRecord(row: $0).model }
        }
        return items ?? []
    }

    // MARK: - Mutations (throwing per the port contract)

    public func save(_ item: WorkItem) async throws {
        let actor = self.actor
        try await queue.write { db in
            let old = try Row.fetchOne(
                db,
                sql: "SELECT * FROM work_item WHERE id = ?",
                arguments: [item.id.uuid.uuidString]
            ).map { WorkItemRecord(row: $0).model }

            try db.execute(
                sql: """
                    INSERT INTO work_item (
                      id, kind, parent_id, title, description_md, status, priority,
                      start_at, end_at, completed_at, display_order, color, tags_json,
                      created_at, updated_at, deleted_at, version, device_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                      kind = excluded.kind,
                      parent_id = excluded.parent_id,
                      title = excluded.title,
                      description_md = excluded.description_md,
                      status = excluded.status,
                      priority = excluded.priority,
                      start_at = excluded.start_at,
                      end_at = excluded.end_at,
                      completed_at = excluded.completed_at,
                      display_order = excluded.display_order,
                      color = excluded.color,
                      tags_json = excluded.tags_json,
                      updated_at = excluded.updated_at,
                      deleted_at = excluded.deleted_at,
                      version = excluded.version,
                      device_id = excluded.device_id
                    """,
                arguments: [
                    item.id.uuid.uuidString,
                    item.kind.rawValue,
                    item.parentId?.uuid.uuidString,
                    item.title,
                    item.descriptionMd,
                    item.status.rawValue,
                    item.priority.rawValue,
                    SqlTimestamp.encode(item.startAt),
                    SqlTimestamp.encode(item.endAt),
                    item.completedAt.map(SqlTimestamp.encode),
                    item.displayOrder,
                    item.color,
                    Json.arrayString(item.tags),
                    SqlTimestamp.encode(item.createdAt),
                    SqlTimestamp.encode(item.updatedAt),
                    item.deletedAt.map(SqlTimestamp.encode),
                    item.version,
                    item.deviceId,
                ]
            )
            try Outbox.append(
                db,
                entity: "work_item",
                entityId: item.id.uuid.uuidString,
                op: "upsert",
                payloadJson: (try? Json.encode(item)) ?? "{}",
                at: item.updatedAt
            )

            for event in Self.events(old: old, new: item, actor: actor) {
                try ActivityLog.append(db, event)
            }
        }
    }

    /// Diffs an upsert into human-readable activity events. Only changes are
    /// emitted, so a no-op save does not spam the log.
    private static func events(
        old: WorkItem?,
        new: WorkItem,
        actor: String
    ) -> [ActivityEvent] {
        let at = new.updatedAt
        let device = new.deviceId
        func event(
            _ kind: ActivityEvent.Kind,
            _ summary: String,
            metadata: [String: String] = [:]
        ) -> ActivityEvent {
            ActivityEvent(
                itemId: new.id,
                kind: kind,
                summary: summary,
                actor: actor,
                occurredAt: at,
                metadata: metadata,
                deviceId: device
            )
        }

        guard let old else {
            return [
                event(
                    .created,
                    "Created “\(new.title)”",
                    metadata: [
                        "kind": new.kind.rawValue,
                        "priority": new.priority.label,
                        "due": ISO8601DateFormatter().string(from: new.endAt),
                        "parent_id": new.parentId?.uuid.uuidString ?? "",
                    ].filter { !$0.value.isEmpty }
                )
            ]
        }

        var events: [ActivityEvent] = []

        if old.deletedAt == nil, new.deletedAt != nil {
            events.append(event(.deleted, "Deleted “\(old.title)”"))
        } else if old.deletedAt != nil, new.deletedAt == nil {
            events.append(event(.other, "Restored “\(new.title)”"))
        }

        if old.status != new.status {
            if new.status == .done {
                events.append(event(.completed, "Completed “\(new.title)”"))
            } else if old.status == .done {
                events.append(event(.reopened, "Reopened “\(new.title)”"))
            } else {
                events.append(
                    event(
                        .statusChanged,
                        "Status: \(old.status.label) → \(new.status.label)",
                        metadata: ["old": old.status.rawValue, "new": new.status.rawValue]
                    )
                )
            }
        }

        if old.priority != new.priority {
            events.append(
                event(
                    .priorityChanged,
                    "Priority: \(old.priority.label) → \(new.priority.label)",
                    metadata: [
                        "old": old.priority.label,
                        "new": new.priority.label,
                    ]
                )
            )
        }

        if old.startAt != new.startAt || old.endAt != new.endAt {
            events.append(
                event(
                    .scheduled,
                    "Dates: \(Self.range(old)) → \(Self.range(new))",
                    metadata: [
                        "old_start": ISO8601DateFormatter().string(from: old.startAt),
                        "old_end": ISO8601DateFormatter().string(from: old.endAt),
                        "new_start": ISO8601DateFormatter().string(from: new.startAt),
                        "new_end": ISO8601DateFormatter().string(from: new.endAt),
                    ]
                )
            )
        }

        if old.parentId != new.parentId {
            events.append(
                event(
                    .reparented,
                    new.parentId == nil ? "Moved to top level" : "Moved under another item",
                    metadata: [
                        "old_parent": old.parentId?.uuid.uuidString ?? "",
                        "new_parent": new.parentId?.uuid.uuidString ?? "",
                    ]
                )
            )
        } else if old.displayOrder != new.displayOrder {
            events.append(event(.reordered, "Reordered"))
        }

        if old.title != new.title {
            events.append(
                event(
                    .edited,
                    "Renamed to “\(new.title)”",
                    metadata: ["old_title": old.title]
                )
            )
        } else if old.descriptionMd != new.descriptionMd {
            events.append(event(.edited, "Edited description"))
        }

        return events
    }

    private static func range(_ item: WorkItem) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return "\(formatter.string(from: item.startAt))–\(formatter.string(from: item.endAt))"
    }

    public func softDelete(_ id: UUIDv7, at: Date) async throws {
        try await queue.write { db in
            let idString = id.uuid.uuidString
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM work_item WHERE id = ? AND deleted_at IS NULL",
                arguments: [idString]
            )
            guard let row else { return } // idempotent: missing or already deleted
            let stamp = SqlTimestamp.encode(at)
            try db.execute(
                sql: """
                    UPDATE work_item
                    SET deleted_at = ?, updated_at = ?, version = version + 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [stamp, stamp, idString]
            )
            var tombstone = WorkItemRecord(row: row).model
            tombstone.deletedAt = at
            tombstone.updatedAt = at
            tombstone.version = (row["version"] as Int) + 1
            try Outbox.append(
                db,
                entity: "work_item",
                entityId: idString,
                op: "upsert",
                payloadJson: (try? Json.encode(tombstone)) ?? "{}",
                at: at
            )
            try ActivityLog.append(
                db,
                ActivityEvent(
                    itemId: id,
                    kind: .deleted,
                    summary: "Deleted “\(tombstone.title)”",
                    actor: actor,
                    occurredAt: at,
                    deviceId: tombstone.deviceId
                )
            )
        }
    }

    public func move(
        _ id: UUIDv7,
        toParent: UUIDv7?,
        displayOrder: String,
        at: Date
    ) async throws {
        try await queue.write { db in
            let idString = id.uuid.uuidString
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM work_item WHERE id = ? AND deleted_at IS NULL",
                arguments: [idString]
            )
            guard let row else { return } // idempotent: missing or already deleted
            let stamp = SqlTimestamp.encode(at)
            try db.execute(
                sql: """
                    UPDATE work_item
                    SET parent_id = ?, display_order = ?, updated_at = ?, version = version + 1
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [toParent?.uuid.uuidString, displayOrder, stamp, idString]
            )
            var moved = WorkItemRecord(row: row).model
            moved.parentId = toParent
            moved.displayOrder = displayOrder
            moved.updatedAt = at
            moved.version = (row["version"] as Int) + 1
            try Outbox.append(
                db,
                entity: "work_item",
                entityId: idString,
                op: "upsert",
                payloadJson: (try? Json.encode(moved)) ?? "{}",
                at: at
            )

            let reparented = moved.parentId != (row["parent_id"] as String?).map { UUIDv7(databaseString: $0) }
            try ActivityLog.append(
                db,
                ActivityEvent(
                    itemId: id,
                    kind: reparented ? .reparented : .reordered,
                    summary: reparented ? "Moved under another item" : "Reordered",
                    actor: actor,
                    occurredAt: at,
                    metadata: [
                        "old_parent": (row["parent_id"] as String?) ?? "",
                        "new_parent": toParent?.uuid.uuidString ?? "",
                        "display_order": displayOrder,
                    ],
                    deviceId: moved.deviceId
                )
            )
        }
    }

    // MARK: - Observation

    /// Re-emits the today list whenever the underlying rows change.
    ///
    /// Uses the `.task` scheduler (no main-actor dependency, safe off the main
    /// thread) and cancels the observation when the stream terminates.
    public func observeToday(on day: Date, calendar: WorkCalendar) async -> AsyncStream<[WorkItem]> {
        AsyncStream { continuation in
            let dayEnd = SqlTimestamp.encode(calendar.endOfDay(for: day))
            let observation = ValueObservation.tracking { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM work_item
                        WHERE deleted_at IS NULL
                          AND status NOT IN ('done', 'cancelled')
                          AND start_at < ?
                        ORDER BY display_order
                        """,
                    arguments: [dayEnd]
                )
                return rows.map { WorkItemRecord(row: $0).model }
            }
            let cancellable = observation.start(
                in: queue,
                scheduling: .task,
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) }
            )
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
}
