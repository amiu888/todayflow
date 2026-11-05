import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

private func reminderDate(_ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour))!
}

struct ReminderRepositoryTests {
    @Test func saveReadPendingAndDelete() async throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        defer { try? queue.close() }
        let items = GRDBWorkItemRepository(queue: queue)
        let reminders = GRDBReminderRepository(queue: queue, actor: "tester")
        let activity = GRDBActivityRepository(queue: queue)

        let item = WorkItem(title: "Ship")
        try await items.save(item)
        let reminder = Reminder(
            itemId: item.id,
            kind: .task,
            fireAt: reminderDate(15),
            createdAt: reminderDate(9)
        )

        try await reminders.save(reminder)

        #expect(await reminders.reminder(for: item.id, kind: .task)?.id == reminder.id)
        #expect(await reminders.pending(after: reminderDate(10)).map(\.id) == [reminder.id])

        let events = await activity.events(for: item.id)
        #expect(events.contains { $0.kind == .reminderSet && $0.actor == "tester" })

        try await reminders.delete(reminder.id)
        #expect(await reminders.reminder(for: item.id, kind: .task) == nil)
        let cleared = await activity.events(for: item.id)
        #expect(cleared.contains { $0.kind == .reminderCleared })
    }

    @Test func pendingSkipsPastAndDeliveredReminders() async throws {
        let queue = try TodayFlowDatabase.makeInMemory()
        defer { try? queue.close() }
        let items = GRDBWorkItemRepository(queue: queue)
        let reminders = GRDBReminderRepository(queue: queue)
        let item = WorkItem(title: "Ship")
        try await items.save(item)

        let past = Reminder(itemId: item.id, kind: .task, fireAt: reminderDate(8))
        let delivered = Reminder(
            itemId: item.id,
            kind: .task,
            fireAt: reminderDate(16),
            deliveredAt: reminderDate(16)
        )
        try await reminders.save(past)
        try await reminders.save(delivered)

        #expect(await reminders.pending(after: reminderDate(10)).isEmpty)
    }
}
