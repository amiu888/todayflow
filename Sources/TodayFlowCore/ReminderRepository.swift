import Foundation

/// Port for per-task reminders (driver.md FR-42 "plus each task's own
/// reminder"). Reminders are optional and independent of the automatic
/// end-of-day nudges.
public protocol ReminderRepository: Sendable {
    /// The task reminder for one item, if set.
    func reminder(for itemId: UUIDv7, kind: Reminder.Kind) async -> Reminder?

    /// Insert or update a reminder (upsert by id).
    func save(_ reminder: Reminder) async throws

    /// Hard-delete a reminder.
    func delete(_ id: UUIDv7) async throws

    /// Undelivered task reminders scheduled after `date`.
    func pending(after date: Date) async -> [Reminder]
}
