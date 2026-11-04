import Foundation

/// Port for the app's secret store (driver.md line 411: "API key — stored in
/// Keychain"; NFR-10: API keys in Keychain).
///
/// Conformance contract (same as `SettingRepository`): reads are non-throwing
/// (nil on failure), mutations throw.
public protocol KeychainStore: Sendable {
    /// The secret stored under `key`, or `nil` if absent or unreadable.
    func read(_ key: String) async -> String?

    /// Stores `value` under `key`, replacing any existing value. An empty
    /// string is stored as-is; callers that treat "empty" as "no secret"
    /// should call `delete` instead.
    func write(_ value: String, for key: String) async throws

    /// Removes the secret stored under `key` (a no-op if the key is absent).
    func delete(_ key: String) async throws
}

/// Keys under which the app stores secrets (parallel to `SettingKeys`).
public enum KeychainKeys {
    /// The AI endpoint's API key (driver.md §8).
    public static let aiAPIKey = "ai_api_key"
}

/// In-memory `KeychainStore` for previews and tests.
public actor InMemoryKeychainStore: KeychainStore {
    private var secrets: [String: String] = [:]

    public init() {}

    public func read(_ key: String) async -> String? {
        secrets[key]
    }

    public func write(_ value: String, for key: String) async throws {
        secrets[key] = value
    }

    public func delete(_ key: String) async throws {
        secrets[key] = nil
    }

    /// Test helper: insert a secret directly.
    public func seed(_ value: String, for key: String) {
        secrets[key] = value
    }
}
