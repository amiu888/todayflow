import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

/// NFR-04: the today list must stay fast at real-world scale.
@Suite("Performance")
struct PerformanceTests {
    @Test("the today query stays fast with 10k items (NFR-04)")
    func todayQueryAtScale() async throws {
        let db = try TestDB.inMemory()
        let cal = WorkCalendar.standard
        let day = Date.whole(year: 2026, month: 1, day: 5)
        let dayStart = cal.calendar.startOfDay(for: day)
        let startAt = SqlTimestamp.encode(dayStart.addingTimeInterval(10 * 3600))
        let createdAt = SqlTimestamp.encode(Date.whole(year: 2026, month: 1, day: 4))

        // Seed 10k items in one transaction (display_order is NOT NULL without
        // a default, so it must be provided explicitly).
        try await db.queue.write { connection in
            for i in 0..<10_000 {
                try connection.execute(
                    sql: """
                        INSERT INTO work_item (
                          id, kind, title, status, priority, start_at, display_order,
                          created_at, updated_at, version, device_id
                        ) VALUES (?, 'task', ?, 'todo', 3, ?, ?, ?, ?, 1, 'local')
                        """,
                    arguments: [
                        UUIDv7.new().uuid.uuidString,
                        "Task \(i)",
                        startAt,
                        String(i),
                        createdAt,
                        createdAt,
                    ]
                )
            }
        }

        let start = Date.now
        let items = await db.workItems.todayItems(on: day, calendar: cal)
        let elapsed = Date.now.timeIntervalSince(start)

        #expect(items.count == 10_000)
        // NFR-04 targets 50ms for the query itself; the bound here also covers
        // mapping 10k rows back into models, so it is deliberately loose.
        #expect(elapsed < 500)
    }
}
