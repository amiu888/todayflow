import Foundation

/// Port for the app settings store (driver.md §6 `setting` table:
/// `key TEXT PRIMARY KEY, value_json TEXT NOT NULL`).
///
/// Values are opaque JSON strings; the typed settings values live in
/// `AppSettings.swift`, and the view models do the encode/decode.
///
/// Conformance contract (same as `WorkItemRepository`): reads are
/// non-throwing (nil on failure), mutations throw.
public protocol SettingRepository: Sendable {
    /// The JSON value stored under `key`, or `nil` if the key is absent.
    func value(for key: String) async -> String?

    /// Stores `valueJson` under `key`, replacing any existing value.
    func set(_ valueJson: String, for key: String) async throws

    /// Removes the value stored under `key` (a no-op if the key is absent).
    func remove(_ key: String) async throws
}

/// In-memory `SettingRepository` for previews and tests.
public actor InMemorySettingRepository: SettingRepository {
    private var values: [String: String] = [:]

    public init() {}

    public func value(for key: String) async -> String? {
        values[key]
    }

    public func set(_ valueJson: String, for key: String) async throws {
        values[key] = valueJson
    }

    public func remove(_ key: String) async throws {
        values[key] = nil
    }

    /// Test helper: insert a value directly.
    public func seed(_ valueJson: String, for key: String) {
        values[key] = valueJson
    }
}
