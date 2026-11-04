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

    public init(queue: DatabaseQueue) {
        self.queue = queue
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
        let eob = SqlTimestamp.encode(calendar.endOfBusiness(for: day))
        let items = try? await queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item
                    WHERE deleted_at IS NULL
                      AND status NOT IN ('done', 'cancelled')
                      AND start_at <= ?
                    ORDER BY display_order
                    """,
                arguments: [eob]
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
        try await queue.write { db in
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
        }
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
        }
    }

    // MARK: - Observation

    /// Re-emits the today list whenever the underlying rows change.
    ///
    /// Uses the `.task` scheduler (no main-actor dependency, safe off the main
    /// thread) and cancels the observation when the stream terminates.
    public func observeToday(on day: Date, calendar: WorkCalendar) async -> AsyncStream<[WorkItem]> {
        AsyncStream { continuation in
            let eob = SqlTimestamp.encode(calendar.endOfBusiness(for: day))
            let observation = ValueObservation.tracking { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM work_item
                        WHERE deleted_at IS NULL
                          AND status NOT IN ('done', 'cancelled')
                          AND start_at <= ?
                        ORDER BY display_order
                        """,
                    arguments: [eob]
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
