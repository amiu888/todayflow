import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowPersistence

private func backupDirectory() -> URL {
    URL.temporaryDirectory.appendingPathComponent("TodayFlowBackupTests-\(UUID().uuidString)", isDirectory: true)
}

private func backupDate(_ day: Int, hour: Int = 12) -> Date {
    Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 11, day: day, hour: hour)
    )!
}

struct DatabaseBackupTests {
    @Test func run_createsASnapshotThatCanBeOpened() async throws {
        let directory = backupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = try TodayFlowDatabase.makeInMemory()
        let items = GRDBWorkItemRepository(queue: queue)
        try await items.save(WorkItem(title: "Backed up"))

        let file = try await DatabaseBackup(directory: directory, keep: 7)
            .run(queue: queue, at: backupDate(4))

        let url = try #require(file)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // The snapshot is a normal migrated database with the item in it.
        let restored = try DatabaseQueue(path: url.path)
        let titles = try await restored.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM work_item")
        }
        #expect(titles == ["Backed up"])
    }

    @Test func run_isIdempotentWithinADay() async throws {
        let directory = backupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = try TodayFlowDatabase.makeInMemory()
        let backup = DatabaseBackup(directory: directory, keep: 7)

        let first = try await backup.run(queue: queue, at: backupDate(4, hour: 9))
        let second = try await backup.run(queue: queue, at: backupDate(4, hour: 18))

        #expect(first != nil)
        #expect(second == nil)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
    }

    @Test func run_prunesToTheRetentionLimit() async throws {
        let directory = backupDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = try TodayFlowDatabase.makeInMemory()
        let backup = DatabaseBackup(directory: directory, keep: 3)

        for day in 1...5 {
            try await backup.run(queue: queue, at: backupDate(day))
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
        #expect(files.count == 3)
        #expect(files == [
            "todayflow-2026-11-03.sqlite",
            "todayflow-2026-11-04.sqlite",
            "todayflow-2026-11-05.sqlite",
        ])
    }
}
