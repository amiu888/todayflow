#if canImport(Security)
import Foundation
import Security
import Testing
import TodayFlowCore
import TodayFlowMac

/// Exercises the real macOS Keychain under a test-only service so the tests
/// never touch the app's own items. Each test uses a unique account because
/// Swift Testing runs tests concurrently and the Keychain is a shared system
/// resource.
struct SecurityKeychainStoreTests {
    private static let testService = "TodayFlow-Tests"

    /// A store, or `nil` when the Keychain is unreachable from this process
    /// (locked keychain / no GUI session) — the tests then record an issue
    /// and skip instead of failing.
    private static func availableStore() async -> SecurityKeychainStore? {
        let store = SecurityKeychainStore(service: testService)
        let probe = "probe-\(UUID().uuidString)"
        do {
            try await store.write("probe", for: probe)
            try await store.delete(probe)
            return store
        } catch {
            return nil
        }
    }

    @Test
    func readAbsentKeyReturnsNil() async {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        #expect(await store.read("absent-\(UUID().uuidString)") == nil)
    }

    @Test
    func writeThenReadRoundTrips() async throws {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        let key = "roundtrip-\(UUID().uuidString)"
        try await store.write("sk-test", for: key)
        #expect(await store.read(key) == "sk-test")
        try? await store.delete(key)
    }

    /// A second write of the same account must update in place (the
    /// `errSecDuplicateItem` → `SecItemUpdate` path), not fail.
    @Test
    func writeTwiceUpdatesInPlace() async throws {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        let key = "update-\(UUID().uuidString)"
        try await store.write("v1", for: key)
        try await store.write("v2", for: key)
        #expect(await store.read(key) == "v2")
        try? await store.delete(key)
    }

    @Test
    func deleteRemovesTheItem() async throws {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        let key = "delete-\(UUID().uuidString)"
        try await store.write("secret", for: key)
        try await store.delete(key)
        #expect(await store.read(key) == nil)
    }

    @Test
    func deleteAbsentKeyIsANoop() async throws {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        try await store.delete("absent-\(UUID().uuidString)")
    }

    /// Items are scoped by the Keychain service: the same account under a
    /// different service is a different item.
    @Test
    func itemsAreScopedByService() async throws {
        guard let store = await Self.availableStore() else {
            Issue.record("Keychain unavailable in this session; skipped")
            return
        }
        let other = SecurityKeychainStore(service: "TodayFlow-Tests-Other")
        let key = "scoped-\(UUID().uuidString)"
        try await store.write("visible", for: key)
        #expect(await other.read(key) == nil)
        #expect(await store.read(key) == "visible")
        try? await store.delete(key)
    }
}
#endif
