import Foundation

/// In-memory `ReminderRepository` for tests and previews.
public actor InMemoryReminderRepository: ReminderRepository {
    private var reminders: [UUIDv7: Reminder] = [:]

    public init() {}

    public func reminder(for itemId: UUIDv7, kind: Reminder.Kind) async -> Reminder? {
        reminders.values
            .filter { $0.itemId == itemId && $0.kind == kind }
            .sorted { $0.fireAt < $1.fireAt }
            .first
    }

    public func save(_ reminder: Reminder) async throws {
        reminders[reminder.id] = reminder
    }

    public func delete(_ id: UUIDv7) async throws {
        reminders.removeValue(forKey: id)
    }

    public func pending(after date: Date) async -> [Reminder] {
        reminders.values
            .filter { $0.deliveredAt == nil && $0.fireAt > date }
            .sorted { $0.fireAt < $1.fireAt }
    }

    // MARK: Test helpers

    public func seed(_ reminder: Reminder) {
        reminders[reminder.id] = reminder
    }

    public var all: [Reminder] { Array(reminders.values) }
}
