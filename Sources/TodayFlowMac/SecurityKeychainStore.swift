#if canImport(Security)
import Foundation
import Security
import TodayFlowCore

/// An error from the macOS Keychain, carrying the underlying `OSStatus`.
public struct KeychainError: Error, CustomStringConvertible {
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
}

/// Production `KeychainStore` backed by the macOS Keychain (driver.md
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
            let status = SecItemUpdate(query(for: key) as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError(operation: .update, status: status)
            }
        case let status:
            throw KeychainError(operation: .add, status: status)
        }
    }

    public func delete(_ key: String) async throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(operation: .delete, status: status)
        }
    }

    // MARK: Query

    private func query(for key: String) -> [String: AnyObject] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as NSString,
            kSecAttrAccount as String: key as NSString,
            kSecReturnData as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
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
