#if canImport(Security)
import Foundation
import Security
import TodayFlowCore

/// An error from the Keychain, carrying the underlying `OSStatus`.
public struct KeychainError: LocalizedError, CustomStringConvertible {
    public enum Operation: String, Sendable {
        case add
        case update
        case delete
    }

    public let operation: Operation
    public let status: OSStatus

    public var description: String {
        "Keychain \(operation.rawValue) failed with status \(status)"
    }

    public var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Couldn't save to the Keychain (\(operation.rawValue)): \(reason)"
    }
}

/// Production `KeychainStore` backed by the Keychain (driver.md
/// line 411 / NFR-10: API keys in Keychain).
///
/// Secrets are stored as generic passwords scoped by `service`:
/// `(service, key)` → UTF-8 data. A `final` class with no mutable state,
/// so it is implicitly `Sendable`.
public final class SecurityKeychainStore: KeychainStore {
    /// The Keychain service name scoping this app's items.
    public let service: String

    public init(service: String = "TodayFlow") {
        self.service = service
    }

    // MARK: KeychainStore

    public func read(_ key: String) async -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query(for: key) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, for key: String) async throws {
        let data = Data(value.utf8)
        switch SecItemAdd(attributes(for: key, data: data) as CFDictionary, nil) {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let update: [String: AnyObject] = [kSecValueData as String: data as NSData]
            // SecItemUpdate takes the item's identity only: iOS rejects a
            // query that also asks for data back (errSecParam).
            let status = SecItemUpdate(identity(for: key) as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError(operation: .update, status: status)
            }
        case let status:
            throw KeychainError(operation: .add, status: status)
        }
    }

    public func delete(_ key: String) async throws {
        let status = SecItemDelete(identity(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: .delete, status: status)
        }
    }

    // MARK: Query

    /// Which item: used by update and delete.
    private func identity(for key: String) -> [String: AnyObject] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as NSString,
            kSecAttrAccount as String: key as NSString,
        ]
    }

    /// Which item, returning its data: used by read.
    private func query(for key: String) -> [String: AnyObject] {
        var query = identity(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func attributes(for key: String, data: Data) -> [String: AnyObject] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as NSString,
            kSecAttrAccount as String: key as NSString,
            kSecValueData as String: data as NSData,
        ]
    }
}
#endif
