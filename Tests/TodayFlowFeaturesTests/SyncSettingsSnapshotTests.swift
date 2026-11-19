#if canImport(AppKit)
import AppKit
import Observation
import SwiftUI
import Testing
@testable import TodayFlowFeatures
import TodayFlowCore
import TodayFlowDesign

@MainActor
@Observable
final class FakeSyncBackend: SyncPanelBackend {
    var snapshot = SyncSnapshot()
    var pairedWith: (String, String)?
    var pairError: String?

    func pair(server: String, code: String) async -> String? {
        if let pairError { return pairError }
        pairedWith = (server, code)
        snapshot.isPaired = true
        snapshot.serverAddress = server
        return nil
    }
    func unpair() async { snapshot = SyncSnapshot() }
    func setEnabled(_ enabled: Bool) async { snapshot.isEnabled = enabled }
    func syncNow() async {}
    func refresh() async {}
}

/// Renders Settings ▸ Sync for a visual check.
/// `TODAYFLOW_WRITE_SYNC_IMAGES=<folder> swift test --filter SyncSettingsSnapshot`
@MainActor
struct SyncSettingsSnapshotTests {
    @Test func pairing_reportsSuccessToTheBackend() async {
        let backend = FakeSyncBackend()
        #expect(await backend.pair(server: "http://nas.local:8787", code: "abc") == nil)
        #expect(backend.snapshot.isPaired)
    }

    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_SYNC_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let unpaired = FakeSyncBackend()
        let paired = FakeSyncBackend()
        paired.snapshot.isPaired = true
        paired.snapshot.serverAddress = "http://nas.local:8787"
        paired.snapshot.deviceName = "Studio Mac"
        paired.snapshot.isEnabled = true
        paired.snapshot.lastSyncAt = Date().addingTimeInterval(-40)
        paired.snapshot.pendingCount = 0
        paired.snapshot.lastResult = "Received 12, sent 3"
        paired.snapshot.log = [
            SyncLogEntry(time: Date().addingTimeInterval(-20), summary: "Sent 2", details: ["Sent task “Plan trip to Lisbon”", "Sent completed task “Call Ana”", "2 history entries (who changed what, when)"]),
            SyncLogEntry(time: Date().addingTimeInterval(-300), summary: "Received 1, 1 file(s) down", details: ["Received attachment “Pasted image”", "Downloaded Pasted image"]),
            SyncLogEntry(time: Date().addingTimeInterval(-900), summary: "Can't reach the server: The request timed out.", isError: true),
        ]
        let failing = FakeSyncBackend()
        failing.snapshot = paired.snapshot
        failing.snapshot.lastError = "Can't reach the server: The request timed out."

        for (name, backend) in [("unpaired", unpaired), ("paired", paired), ("error", failing)] {
            for scheme in [ColorScheme.light, .dark] {
                let view = Form { SyncSettingsSection(backend: backend) }
                    .formStyle(.grouped)
                    .frame(width: 600, height: 640)
                    .environment(\.colorScheme, scheme)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 600, height: 640)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try #require(rep.representation(using: .png, properties: [:]))
                try data.write(to: root.appendingPathComponent("sync-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
#endif

#if canImport(AppKit)
/// The Today header with sync badges.
/// `TODAYFLOW_WRITE_SYNC_IMAGES=<folder> swift test --filter SyncBadgeSnapshot`
@MainActor
struct SyncBadgeSnapshotTests {
    @Test func helpText_explainsTheState() {
        let waiting = SyncBadge.helpText(target: .server, status: .init(state: .waiting(3)))
        #expect(waiting.contains("3 changes on this Mac haven't reached the server"))
        #expect(SyncBadge.helpText(target: .server, status: .init(state: .synced)).hasPrefix("Green: everything on this Mac is on the server"))
        #expect(SyncBadge.helpText(target: .obsidian, status: .init(state: .failed("Vault missing"))).contains("Vault missing"))
    }

    @Test func writeImages() async throws {
        guard let folder = ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_SYNC_IMAGES"] else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let items = InMemoryWorkItemRepository()
        let now = Date()
        await items.seed(WorkItem(title: "Review the quarterly roadmap", priority: .urgent, startAt: now, endAt: now.addingTimeInterval(3600), displayOrder: "a"))
        await items.seed(WorkItem(title: "Prepare customer notes", startAt: now, endAt: now.addingTimeInterval(7200), displayOrder: "b"))
        let today = TodayViewModel(repository: items, linkRepository: InMemoryLinkRepository(), attachmentRepository: InMemoryAttachmentRepository())
        await today.load()

        let cases: [(String, SyncBadgeStatus?, SyncBadgeStatus?)] = [
            ("synced", .init(state: .synced, lastSyncAt: now), .init(state: .synced, lastSyncAt: now)),
            ("mixed", .init(state: .waiting(4)), .init(state: .failed("The Obsidian vault folder no longer exists."))),
            ("server-only", .init(state: .off), nil),
        ]
        for (name, server, obsidian) in cases {
            let badges = SyncBadgesModel()
            badges.server = server
            badges.obsidian = obsidian
            let view = TodayView(
                model: today,
                onNewTask: {}, onOpenContacts: {}, onOpenAllTasks: {}, onOpenSettings: {},
                windowActions: WindowMenuActions(toggleDocking: {}, toggleAllDesktops: {}, toggleMiniCalendar: {}, showMiniDay: {}, showMiniWeek: {}, pinMiniCalendar: { _ in }),
                syncBadges: badges
            )
            for scheme in [ColorScheme.dark, .light] {
                let host = NSHostingView(rootView: view.frame(width: 360, height: 640)
                    .environment(\.colorScheme, scheme)
                    .background(DesignTokens.Palette.background))
                host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 360, height: 640)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                try await Task.sleep(for: .milliseconds(300))
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try #require(rep.representation(using: .png, properties: [:]))
                    .write(to: root.appendingPathComponent("badges-\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
#endif
