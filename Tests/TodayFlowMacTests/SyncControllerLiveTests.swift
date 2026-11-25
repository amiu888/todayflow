import Foundation
import Testing
import TodayFlowCore
import TodayFlowPersistence
@testable import TodayFlowFeatures
@testable import TodayFlowMac

/// Settings ▸ Sync's controller against a real server:
/// `TODAYFLOW_E2E_URL=… TODAYFLOW_E2E_CODE=… swift test --filter SyncControllerLive`
@MainActor
struct SyncControllerLiveTests {
    nonisolated static let url = ProcessInfo.processInfo.environment["TODAYFLOW_E2E_URL"]
    nonisolated static let code = ProcessInfo.processInfo.environment["TODAYFLOW_E2E_CODE"]

    @Test func wrongCode_isExplained() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let dbURL = folder.appendingPathComponent("todayflow.sqlite")
        let controller = SyncController(
            queue: try TodayFlowDatabase.make(at: dbURL), databaseURL: dbURL,
            settings: InMemorySettingRepository(), keychain: InMemoryKeychainStore()
        )
        let error = await controller.pair(server: "http://example.com", code: "x")
        #expect(error?.contains("https://") == true)
        #expect(!controller.snapshot.isPaired)
        #expect(controller.badgeStatus == nil) // no badge until paired
    }

    @Test(.enabled(if: url != nil && code != nil))
    func pairTurnOnAndSync() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tf-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let dbURL = folder.appendingPathComponent("todayflow.sqlite")
        let queue = try TodayFlowDatabase.make(at: dbURL)
        let items = GRDBWorkItemRepository(queue: queue)
        let existing = WorkItem(title: "Existing before pairing")
        try await items.save(existing)

        let keychain = InMemoryKeychainStore()
        let settings = InMemorySettingRepository()
        let controller = SyncController(queue: queue, databaseURL: dbURL, settings: settings, keychain: keychain)
        await controller.start()

        #expect(await controller.pair(server: Self.url!, code: "  \(Self.code!) ") == nil)
        #expect(controller.snapshot.isPaired)
        #expect(!controller.snapshot.isEnabled)
        #expect(controller.snapshot.userName == "E2E")
        #expect(controller.snapshot.pendingCount > 0)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("Backups").path)
        #expect(backups.contains { $0.hasPrefix("before-sync-") })

        await controller.setEnabled(true)
        for _ in 0..<50 where controller.snapshot.lastSyncAt == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(controller.snapshot.lastError == nil)
        #expect(controller.snapshot.lastSyncAt != nil)
        #expect(controller.snapshot.pendingCount == 0)

        // The pairing survives a restart.
        let again = SyncController(queue: queue, databaseURL: dbURL, settings: settings, keychain: keychain)
        await again.start()
        #expect(again.snapshot.isPaired && again.snapshot.isEnabled)
        await again.setEnabled(false)
        await controller.setEnabled(false)

        await again.unpair()
        #expect(!again.snapshot.isPaired)
        #expect(await keychain.read(SyncController.tokenKey) == nil)
    }
}
