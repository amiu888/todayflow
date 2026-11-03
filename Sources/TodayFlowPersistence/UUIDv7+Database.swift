import Foundation
import TodayFlowCore

extension UUIDv7 {
    /// Parses a canonical UUID string read from the database back into a `UUIDv7`.
    ///
    /// Traps on malformed input. This is only ever fed values this app itself wrote
    /// (the `id` / `*_id` TEXT columns are always canonical UUIDv7 strings), so a
    /// trap here indicates database corruption rather than a user-facing error.
    init(databaseString: String) {
        self.init(UUID(uuidString: databaseString)!)
    }
}
