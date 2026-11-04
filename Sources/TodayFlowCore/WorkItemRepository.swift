import Foundation

/// Port for persisting and querying work items (driver.md §6).
///
/// Every method is `async` so the same port is served by an in-memory actor (tests,
/// previews) and by the GRDB-backed production adapter (TodayFlowPersistence). Reads
/// are non-throwing (they return empty/`nil` on failure); mutations throw on error.
///
/// The `WorkCalendar` is passed per call (not stored) so a settings change to the
/// user's business hours takes effect without rebuilding the repository.
public protocol WorkItemRepository: Sendable {
    /// A single live (non-deleted) item, or `nil`.
    func item(_ id: UUIDv7) async -> WorkItem?

    /// The open "Today" list (driver.md FR-10): live, non-terminal items whose
    /// `startAt` is on or before end-of-business on `day`, in display order.
    /// Overdue items (past `endAt`) are included here; the `TodayQuery` use case
    /// partitions them to the top.
    func todayItems(on day: Date, calendar: WorkCalendar) async -> [WorkItem]

    /// Items completed on the calendar day of `day` (the "Done today" section).
    func completedToday(on day: Date, calendar: WorkCalendar) async -> [WorkItem]

    /// Live children of `parentId`, in display order. `nil` means top-level items.
    func children(of parentId: UUIDv7?) async -> [WorkItem]

    /// Every live (non-deleted) item, in display order — the hierarchy tree's
    /// source (driver.md FR-16).
    func allItems() async -> [WorkItem]

    /// Insert or update an item (upsert by `id`).
    func save(_ item: WorkItem) async throws

    /// Soft-delete: stamps `deletedAt`. Children are **not** deleted (driver.md §2).
    func softDelete(_ id: UUIDv7, at: Date) async throws

    /// Change an item's parent and/or display order (drag-to-reparent / reorder).
    func move(_ id: UUIDv7, toParent: UUIDv7?, displayOrder: String, at: Date) async throws

    /// A live stream of the open Today list, re-emitted whenever it changes.
    func observeToday(on day: Date, calendar: WorkCalendar) async -> AsyncStream<[WorkItem]>

    /// Search over titles and descriptions.
    func search(_ query: String) async -> [WorkItem]
}
