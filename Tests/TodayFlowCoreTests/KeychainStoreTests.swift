import Foundation
import Testing
@testable import TodayFlowCore

/// Tests for the `KeychainStore` port and its in-memory implementation
/// (driver.md line 411 / NFR-10: API keys in Keychain).
struct KeychainStoreTests {
    @Test
    func readAbsentKeyReturnsNil() async {
        let store = InMemoryKeychainStore()
        #expect(await store.read(KeychainKeys.aiAPIKey) == nil)
    }

    @Test
    func writeThenReadRoundTrips() async throws {
        let store = InMemoryKeychainStore()
        try await store.write("sk-test", for: KeychainKeys.aiAPIKey)
        #expect(await store.read(KeychainKeys.aiAPIKey) == "sk-test")
    }

    @Test
    func writeReplacesExistingValue() async throws {
        let store = InMemoryKeychainStore()
        try await store.write("old", for: "k")
        try await store.write("new", for: "k")
        #expect(await store.read("k") == "new")
    }

    @Test
    func deleteRemovesValue() async throws {
        let store = InMemoryKeychainStore()
        try await store.write("secret", for: "k")
        try await store.delete("k")
        #expect(await store.read("k") == nil)
    }

    @Test
    func deleteAbsentKeyIsANoop() async throws {
        let store = InMemoryKeychainStore()
        try await store.delete("never-was")
        #expect(await store.read("never-was") == nil)
    }

    @Test
    func seedInsertsDirectly() async {
        let store = InMemoryKeychainStore()
        await store.seed("seeded", for: "k")
        #expect(await store.read("k") == "seeded")
    }
}
