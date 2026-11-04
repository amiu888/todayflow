import Foundation
import GRDB
import TodayFlowCore

/// GRDB adapter for `SettingRepository` (driver.md §6 `setting` table).
///
/// Reads are non-throwing per the port contract (nil on failure); mutations
/// throw. Settings are local app preferences — unlike work items they never
/// touch the `change_outbox` (sync is a v2 concern, driver.md §11).
public final class GRDBSettingRepository: SettingRepository, Sendable {
    private let queue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - Reads (non-throwing per the port contract: nil on failure)

    public func value(for key: String) async -> String? {
        let value = try? await queue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM setting WHERE key = ?",
                arguments: [key]
            ).map { SettingRecord(row: $0).valueJson }
        }
        return value ?? nil
    }

    // MARK: - Mutations (throwing per the port contract)

    public func set(_ valueJson: String, for key: String) async throws {
        try await queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO setting (key, value_json) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json
                    """,
                arguments: [key, valueJson]
            )
        }
    }

    public func remove(_ key: String) async throws {
        try await queue.write { db in
            try db.execute(
                sql: "DELETE FROM setting WHERE key = ?",
                arguments: [key]
            )
        }
    }
}
