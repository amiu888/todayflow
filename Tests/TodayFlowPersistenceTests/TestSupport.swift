import Foundation
import GRDB
import TodayFlowCore
import TodayFlowPersistence

/// A fully wired in-memory (or file-backed) test database.
struct TestDB {
    let queue: DatabaseQueue
    let workItems: GRDBWorkItemRepository
    let links: GRDBLinkRepository
    let attachments: GRDBAttachmentRepository
    let contacts: GRDBContactRepository
    let settings: GRDBSettingRepository
    let outbox: OutboxStore

    static func inMemory() throws -> TestDB {
        let queue = try TodayFlowDatabase.makeInMemory()
        return TestDB(
            queue: queue,
            workItems: GRDBWorkItemRepository(queue: queue),
            links: GRDBLinkRepository(queue: queue),
            attachments: GRDBAttachmentRepository(queue: queue),
            contacts: GRDBContactRepository(queue: queue),
            settings: GRDBSettingRepository(queue: queue),
            outbox: OutboxStore(queue: queue)
        )
    }

    /// A file-backed database in the temporary directory (for persistence tests).
    static func file() throws -> (db: TestDB, path: URL) {
        let path = URL.temporaryDirectory
            .appendingPathComponent("todayflow-test-\(UUID().uuidString).db")
        let queue = try TodayFlowDatabase.make(at: path)
        let db = TestDB(
            queue: queue,
            workItems: GRDBWorkItemRepository(queue: queue),
            links: GRDBLinkRepository(queue: queue),
            attachments: GRDBAttachmentRepository(queue: queue),
            contacts: GRDBContactRepository(queue: queue),
            settings: GRDBSettingRepository(queue: queue),
            outbox: OutboxStore(queue: queue)
        )
        return (db, path)
    }

    /// Closes the queue and removes the database file (and WAL/SHM sidecars).
    func cleanup(_ path: URL?) {
        try? queue.close()
        guard let path else { return }
        for suffix in [path, path.appendingPathExtension("wal"), path.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: suffix)
        }
    }
}

extension Date {
    /// A whole-second UTC date. Whole-second dates round-trip exactly through
    /// `SqlTimestamp` (`.000` fractional), so tests can assert equality.
    static func whole(
        year: Int, month: Int, day: Int,
        hour: Int = 9, minute: Int = 0, second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "UTC")!
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}
