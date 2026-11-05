import Foundation
import GRDB

/// Daily automatic database backups (driver.md NFR-09: daily, keep 7).
///
/// Uses SQLite's `VACUUM INTO`, which writes a consistent snapshot even while
/// WAL mode is active — no need to stop writes or copy the sidecar files.
public struct DatabaseBackup: Sendable {
    public let directory: URL
    public let keep: Int

    public init(directory: URL, keep: Int = 7) {
        self.directory = directory
        self.keep = max(1, keep)
    }

    /// Creates today's backup if it does not exist yet, prunes old snapshots,
    /// and returns the new file (or `nil` when today already had one).
    @discardableResult
    public func run(
        queue: DatabaseQueue,
        at date: Date = .now,
        calendar: Calendar = .current
    ) async throws -> URL? {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(fileName(for: date, calendar: calendar))
        if FileManager.default.fileExists(atPath: destination.path) {
            return nil
        }

        // VACUUM cannot run inside a transaction, hence writeWithoutTransaction.
        try await queue.writeWithoutTransaction { db in
            try db.execute(
                sql: "VACUUM INTO ?",
                arguments: [destination.path]
            )
        }

        prune(calendar: calendar)
        return destination
    }

    private func fileName(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "todayflow-\(formatter.string(from: date)).sqlite"
    }

    /// Keeps the newest `keep` daily snapshots. File names sort by date.
    private func prune(calendar: Calendar) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }

        let backups = files
            .filter {
                $0.lastPathComponent.hasPrefix("todayflow-")
                    && $0.pathExtension == "sqlite"
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for old in backups.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
