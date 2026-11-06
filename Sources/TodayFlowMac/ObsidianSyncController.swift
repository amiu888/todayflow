import AppKit
import Foundation
import TodayFlowCore

/// Optional two-way bridge between TodayFlow and an Obsidian vault.
///
/// The central note owns a managed block. TodayFlow writes the block and reads
/// checkbox/title/tag/due-date changes from it. Everything outside the markers
/// is preserved. The service is inert until Settings configures a vault.
@MainActor
public final class ObsidianSyncController {
    private let workItems: any WorkItemRepository
    private let settings: any SettingRepository
    private let calendar: WorkCalendar
    private let clock: @Sendable () -> Date
    private let deviceId = "local"

    private var loop: Task<Void, Never>?
    private var isSyncing = false
    private var lastWrittenContent: String?
    private var lastConfiguration: ObsidianSettings?

    public private(set) var lastError: String?
    public private(set) var lastSyncAt: Date?

    public init(
        workItems: any WorkItemRepository,
        settings: any SettingRepository,
        calendar: WorkCalendar = .standard,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.workItems = workItems
        self.settings = settings
        self.calendar = calendar
        self.clock = clock
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncTick()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Forces an immediate sync. Returns an error message when the bridge is
    /// not configured or the file could not be read/written.
    @discardableResult
    public func syncNow() async -> String? {
        await syncTick()
        return lastError
    }

    /// Opens the central sync note in Obsidian, creating it first if needed.
    public func openSyncNote() async -> String? {
        guard let config = await loadConfiguration(), config.isConfigured else {
            return "Set up Obsidian in Settings → Obsidian first."
        }
        if let error = await syncNow() {
            return error
        }
        guard let url = ObsidianDeepLink.open(
            vaultName: config.resolvedVaultName,
            notePath: config.normalizedNotePath
        ) else {
            return "The Obsidian vault name or note path is invalid."
        }
        guard NSWorkspace.shared.open(url) else {
            return "Obsidian did not open. Make sure the app is installed."
        }
        return nil
    }

    /// Creates/updates a note for one task or project and opens it in Obsidian.
    /// This is a one-way snapshot; the central sync note is the two-way one.
    public func openNote(for item: WorkItem) async -> String? {
        guard let config = await loadConfiguration(), config.isConfigured,
              let vault = config.vaultURL
        else {
            return "Set up Obsidian in Settings → Obsidian first."
        }
        let folder = item.kind == .project || item.kind == .epic
            ? "TodayFlow/Projects"
            : "TodayFlow/Tasks"
        let relativePath = "\(folder)/\(item.id).md"
        let fileURL = vault.appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let projectTitle: String?
            if let parentId = item.parentId {
                projectTitle = await workItems.item(parentId)?.title
            } else {
                projectTitle = nil
            }
            let content = ObsidianItemNote.render(
                item: item,
                projectTitle: projectTitle,
                now: clock()
            )
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return "Could not write the Obsidian note: \(error.localizedDescription)"
        }

        guard let url = ObsidianDeepLink.open(
            vaultName: config.resolvedVaultName,
            notePath: relativePath
        ) else {
            return "The Obsidian vault name is invalid."
        }
        guard NSWorkspace.shared.open(url) else {
            return "Obsidian did not open. Make sure the app is installed."
        }
        return nil
    }

    // MARK: Sync loop

    private func syncTick() async {
        guard !isSyncing else { return }
        guard let config = await loadConfiguration() else {
            lastWrittenContent = nil
            lastConfiguration = nil
            lastError = nil
            return
        }
        guard config.isConfigured else {
            lastWrittenContent = nil
            lastConfiguration = nil
            lastError = nil
            return
        }
        guard let noteURL = config.noteURL, let vault = config.vaultURL else {
            lastError = "Choose a valid Obsidian vault folder."
            return
        }
        guard FileManager.default.fileExists(atPath: vault.path) else {
            lastError = "The Obsidian vault folder no longer exists."
            return
        }

        if lastConfiguration != config {
            lastWrittenContent = nil
            lastConfiguration = config
        }

        isSyncing = true
        defer { isSyncing = false }
        lastError = nil

        do {
            try FileManager.default.createDirectory(
                at: noteURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let existing = try? String(contentsOf: noteURL, encoding: .utf8)
            if let existing,
               existing != lastWrittenContent,
               existing.contains(ObsidianNote.startMarker)
            {
                try await importChanges(from: existing)
            }

            let all = await workItems.allItems()
            let rendered = ObsidianNote.render(
                items: all,
                projects: all.filter { $0.kind == .project },
                existing: existing,
                now: clock(),
                calendar: calendar
            )
            if rendered != existing {
                try rendered.write(to: noteURL, atomically: true, encoding: .utf8)
            }
            lastWrittenContent = rendered
            lastSyncAt = clock()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Import

    private func importChanges(from note: String) async throws {
        let lines = ObsidianNote.parse(note, calendar: calendar.calendar)
        let now = clock()

        for line in lines {
            var dueEnd: Date?
            if let due = line.dueAt {
                dueEnd = line.dueHasTime ? due : calendar.endOfBusiness(for: due)
            }
            guard let id = line.id else {
                // Checklist lines without IDs become new tasks. Projects are
                // display-only so a stray bold line cannot create a container.
                guard !line.isProject, !line.title.isEmpty else { continue }
                let input = CreateTask.Input(
                    kind: .task,
                    title: line.title,
                    startAt: now,
                    endAt: dueEnd,
                    tags: line.tags,
                    placement: .top
                )
                _ = try await CreateTask(
                    repository: workItems,
                    calendar: calendar,
                    deviceId: deviceId
                ).execute(input)
                continue
            }

            guard var item = await workItems.item(id) else { continue }

            if item.kind == .project || item.kind == .epic {
                guard line.isProject else { continue }
                var changed = false
                if !line.title.isEmpty, line.title != item.title {
                    item.title = line.title
                    changed = true
                }
                if line.tags != item.tags {
                    item.tags = line.tags
                    changed = true
                }
                if changed {
                    item = item.touching(now)
                    item.deviceId = deviceId
                    try await workItems.save(item)
                }
                continue
            }

            var changed = false
            if line.isDone != item.status.isComplete {
                item.status = line.isDone ? .done : .todo
                item.completedAt = line.isDone ? now : nil
                changed = true
            }
            if !line.title.isEmpty, line.title != item.title {
                item.title = line.title
                changed = true
            }
            if line.tags != item.tags {
                item.tags = line.tags
                changed = true
            }
            if let due = dueEnd,
               abs(due.timeIntervalSince(item.endAt)) > 1
            {
                item.endAt = due
                changed = true
            }
            if changed {
                item = item.touching(now)
                item.deviceId = deviceId
                try await workItems.save(item)
            }
        }
    }

    // MARK: Configuration

    private func loadConfiguration() async -> ObsidianSettings? {
        guard let raw = await settings.value(for: SettingKeys.obsidian),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ObsidianSettings.self, from: data)
        else { return nil }
        return decoded
    }
}
