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

    // MARK: Archive

    private func archiveFiles(_ vault: URL) -> [String] {
        let root = vault.appendingPathComponent("TodayFlow")
        let enumerator = FileManager.default.enumerator(atPath: root.path)
        var files: [String] = []
        while let path = enumerator?.nextObject() as? String {
            if path.hasSuffix(".md") || path.hasSuffix(".base") { files.append(path) }
        }
        return files.sorted()
    }

    @Test func exportsEveryTaskWithPeopleAndHistory() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let contacts = InMemoryContactRepository()
        let activity = InMemoryActivityRepository()
        try await configure(settings, vault: vault)

        let old = WorkItem(
            title: "Finished last month",
            status: .done,
            startAt: now.addingTimeInterval(-40 * 86_400),
            endAt: now.addingTimeInterval(-39 * 86_400),
            completedAt: now.addingTimeInterval(-39 * 86_400),
            createdAt: now.addingTimeInterval(-40 * 86_400)
        )
        let open = WorkItem(title: "Call supplier", startAt: now, endAt: now.addingTimeInterval(3_600), createdAt: now)
        await items.seed(old)
        await items.seed(open)
        let maria = Contact(firstName: "Maria", lastName: "Silva")
        try await contacts.save(maria)
        try await contacts.addContact(maria.id, toTask: open.id)
        try await activity.record(ActivityEvent(itemId: open.id, kind: .created, summary: "Created “Call supplier”", occurredAt: now))

        let fixedNow = now
        let service = ObsidianSyncController(
            workItems: items,
            contacts: contacts,
            activities: activity,
            settings: settings,
            keychain: InMemoryKeychainStore(),
            calendar: WorkCalendar(calendar: utc),
            clock: { fixedNow }
        )
        #expect(await service.syncNow() == nil)

        let files = archiveFiles(vault)
        #expect(files.contains("Tasks.md"))
        #expect(files.contains("TodayFlow.base"))
        #expect(files.contains { $0.hasPrefix("Tasks/2026-09/Finished last month (") })
        #expect(files.contains { $0.hasPrefix("Contacts/Maria Silva (") })
        #expect(files.contains("Daily/2026-11-06.md"))

        let taskFile = try #require(files.first { $0.hasPrefix("Tasks/2026-11/Call supplier (") })
        let note = try String(contentsOf: vault.appendingPathComponent("TodayFlow/\(taskFile)"), encoding: .utf8)
        #expect(note.contains("## People\n- [[TodayFlow/Contacts/Maria Silva ("))
        #expect(note.contains("Created “Call supplier”"))
    }

    @Test func renamesAndDeletesFollowTheTaskButLeaveOtherFilesAlone() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        try await configure(settings, vault: vault)
        let mine = vault.appendingPathComponent("TodayFlow/My own note.md")
        try FileManager.default.createDirectory(at: mine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "keep me".write(to: mine, atomically: true, encoding: .utf8)

        var task = WorkItem(title: "Draft budget", startAt: now, endAt: now.addingTimeInterval(3_600), createdAt: now)
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
        #expect(archiveFiles(vault).contains { $0.hasPrefix("Tasks/2026-11/Draft budget (") })

        task.title = "Final budget"
        task = task.touching(now)
        try await items.save(task)
        #expect(await service.syncNow() == nil)
        var files = archiveFiles(vault)
        #expect(files.contains { $0.hasPrefix("Tasks/2026-11/Final budget (") })
        #expect(!files.contains { $0.hasPrefix("Tasks/2026-11/Draft budget (") })

        try await items.softDelete(task.id, at: now)
        #expect(await service.syncNow() == nil)
        files = archiveFiles(vault)
        #expect(files.contains { $0.hasPrefix("Deleted/Final budget (") })
        #expect(!files.contains { $0.hasPrefix("Tasks/2026-11/") })
        #expect(files.contains("My own note.md"))
    }

    @Test func notesRemovedInObsidianAreWrittenAgain() async throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        try await configure(settings, vault: vault)
        await items.seed(WorkItem(title: "Plan offsite", startAt: now, endAt: now.addingTimeInterval(3_600), createdAt: now))
        let fixedNow = now
        let service = ObsidianSyncController(
            workItems: items,
            settings: settings,
            keychain: InMemoryKeychainStore(),
            calendar: WorkCalendar(calendar: utc),
            clock: { fixedNow }
        )
        #expect(await service.syncNow() == nil)
        let file = try #require(archiveFiles(vault).first { $0.hasPrefix("Tasks/2026-11/Plan offsite (") })
        try FileManager.default.removeItem(at: vault.appendingPathComponent("TodayFlow/\(file)"))

        await items.seed(WorkItem(title: "Another", startAt: now, endAt: now.addingTimeInterval(3_600), createdAt: now))
        #expect(await service.syncNow() == nil)
        #expect(archiveFiles(vault).contains(file))
    }
}
#endif
