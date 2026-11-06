#if canImport(AppKit)
import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowMac

@Suite("Obsidian sync")
@MainActor
struct ObsidianSyncTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var now: Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 9))!
    }

    private func makeVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("todayflow-obsidian-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func configure(
        _ settings: InMemorySettingRepository,
        vault: URL
    ) async throws {
        let config = ObsidianSettings(
            enabled: true,
            vaultPath: vault.path,
            vaultName: "Vault",
            notePath: "TodayFlow/Tasks.md"
        )
        let data = try JSONEncoder().encode(config)
        try await settings.set(String(decoding: data, as: UTF8.self), for: SettingKeys.obsidian)
    }

    @Test func disabledObsidianNeverTouchesTheVault() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let fixedNow = now
        let service = ObsidianSyncController(
            workItems: items,
            settings: settings,
            keychain: InMemoryKeychainStore(),
            calendar: WorkCalendar(calendar: utc),
            clock: { fixedNow }
        )

        #expect(await service.syncNow() == nil)
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("TodayFlow/Tasks.md").path))
    }

    @Test func writesTheNoteAndImportsCheckboxChanges() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        try await configure(settings, vault: vault)
        let task = WorkItem(
            title: "Review Q4 roadmap",
            priority: .high,
            startAt: now,
            endAt: utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 17))!,
            displayOrder: "a0",
            tags: ["launch"]
        )
        await items.seed(task)
        let fixedNow = now
        let service = ObsidianSyncController(
            workItems: items,
            settings: settings,
            keychain: InMemoryKeychainStore(),
            calendar: WorkCalendar(calendar: utc),
            clock: { fixedNow }
        )

        #expect(await service.syncNow() == nil)

        let noteURL = vault.appendingPathComponent("TodayFlow/Tasks.md")
        let note = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(note.contains("Review Q4 roadmap"))
        #expect(note.contains("<!-- todayflow:\(task.id) -->"))
        #expect(note.contains("#launch"))

        let edited = note.replacingOccurrences(of: "- [ ] Review Q4 roadmap", with: "- [x] Review Q4 roadmap")
        try edited.write(to: noteURL, atomically: true, encoding: .utf8)
        #expect(await service.syncNow() == nil)

        let updated = await items.item(task.id)
        #expect(updated?.status == .done)
    }

    @Test func newChecklistLinesBecomeTasks() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        try await configure(settings, vault: vault)
        let fixedNow = now
        let service = ObsidianSyncController(
            workItems: items,
            settings: settings,
            keychain: InMemoryKeychainStore(),
            calendar: WorkCalendar(calendar: utc),
            clock: { fixedNow }
        )
        #expect(await service.syncNow() == nil)

        let noteURL = vault.appendingPathComponent("TodayFlow/Tasks.md")
        let note = try String(contentsOf: noteURL, encoding: .utf8)
        let edited = note.replacingOccurrences(
            of: ObsidianNote.endMarker,
            with: "- [ ] From Obsidian #ops 📅 2026-11-07\n\(ObsidianNote.endMarker)"
        )
        try edited.write(to: noteURL, atomically: true, encoding: .utf8)
        #expect(await service.syncNow() == nil)

        let all = await items.allItems()
        let imported = all.first { $0.title == "From Obsidian" }
        #expect(imported != nil)
        #expect(imported?.tags == ["ops"])
        let dateOnly = utc.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        #expect(imported?.endAt == WorkCalendar(calendar: utc).endOfBusiness(for: dateOnly))
    }
}
#endif
