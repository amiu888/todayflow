import AppKit
import Foundation
import TodayFlowCore
import TodayFlowFeatures

/// Optional two-way bridge between TodayFlow and Obsidian.
///
/// The central note owns a managed block. TodayFlow writes the block and reads
/// checkbox/title/tag/due-date changes from it. Everything outside the markers
/// is preserved. The service is inert until Settings configures a vault or a
/// remote Local REST API server.
@MainActor
public final class ObsidianSyncController {
    private let workItems: any WorkItemRepository
    private let links: (any LinkRepository)?
    private let contacts: (any ContactRepository)?
    private let attachments: (any AttachmentRepository)?
    private let activities: (any ActivityRepository)?
    private let settings: any SettingRepository
    private let keychain: any KeychainStore
    private let calendar: WorkCalendar
    private let clock: @Sendable () -> Date
    private let deviceId = "local"

    private var loop: Task<Void, Never>?
    private var isSyncing = false
    private var lastWrittenContent: String?
    private var lastConfiguration: ObsidianSettings?
    /// Change fingerprint of the data last exported to the archive.
    private var archiveFingerprint: String?
    private var archiveExportedAt: Date?
    /// Number of notes in the archive after the last export.
    public private(set) var archiveNoteCount = 0

    public private(set) var lastError: String?
    public private(set) var lastSyncAt: Date?
    /// Called after each round with the header badge (nil: not set up).
    public var onStatusChange: (@MainActor (SyncBadgeStatus?) -> Void)?
    private var lastStatus: SyncBadgeStatus??

    private func report(_ status: SyncBadgeStatus?) {
        guard lastStatus != .some(status) else { return }
        lastStatus = .some(status)
        onStatusChange?(status)
    }

    public init(
        workItems: any WorkItemRepository,
        links: (any LinkRepository)? = nil,
        contacts: (any ContactRepository)? = nil,
        attachments: (any AttachmentRepository)? = nil,
        activities: (any ActivityRepository)? = nil,
        settings: any SettingRepository,
        keychain: any KeychainStore,
        calendar: WorkCalendar = .standard,
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.workItems = workItems
        self.links = links
        self.contacts = contacts
        self.attachments = attachments
        self.activities = activities
        self.settings = settings
        self.keychain = keychain
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
    /// not configured or the note could not be read/written.
    @discardableResult
    public func syncNow() async -> String? {
        await syncTick()
        return lastError
    }

    /// Opens the central sync note, creating it first if needed.
    public func openSyncNote() async -> String? {
        guard let config = await loadConfiguration(), config.isConfigured else {
            return "Set up Obsidian in Settings → Obsidian first."
        }

        if config.mode == .remote {
            guard let client = await remoteClient(for: config) else {
                return lastError ?? "The remote Obsidian connection is not ready."
            }
            if let error = await syncNow() {
                return error
            }
            do {
                try await client.open(config.normalizedNotePath)
                return nil
            } catch {
                return error.localizedDescription
            }
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

    /// Opens the archive note for one task or project, exporting first so
    /// the note exists and is current.
    public func openNote(for item: WorkItem) async -> String? {
        guard let config = await loadConfiguration(), config.isConfigured else {
            return "Set up Obsidian in Settings → Obsidian first."
        }
        archiveFingerprint = nil
        if let error = await syncNow() {
            return error
        }
        let snapshot = await archiveSnapshot()
        guard let relativePath = ObsidianArchive.path(
            for: item.id,
            snapshot: snapshot,
            root: ObsidianArchive.root(forNotePath: config.normalizedNotePath),
            calendar: calendar.calendar
        ) else {
            return "This item is not in the Obsidian archive yet."
        }

        if config.mode == .remote {
            guard let client = await remoteClient(for: config) else {
                return lastError ?? "The remote Obsidian connection is not ready."
            }
            do {
                try await client.open(relativePath)
                return nil
            } catch {
                return error.localizedDescription
            }
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
            report(nil)
            return
        }
        guard config.isConfigured else {
            lastWrittenContent = nil
            lastConfiguration = nil
            lastError = nil
            report(nil)
            return
        }
        defer {
            let place = config.mode == .remote
                ? "Obsidian on \(config.sanitizedRemoteHost):\(config.remotePort)"
                : "Vault: \(config.resolvedVaultName)"
            report(SyncBadgeStatus(
                state: lastError.map { .failed($0) } ?? .synced,
                lastSyncAt: lastSyncAt,
                details: [
                    place,
                    "Note: \(config.normalizedNotePath)",
                    "Archive: \(archiveNoteCount) notes in \(ObsidianArchive.root(forNotePath: config.normalizedNotePath))/",
                ]
            ))
        }

        if lastConfiguration != config {
            lastWrittenContent = nil
            lastConfiguration = config
        }

        isSyncing = true
        defer { isSyncing = false }
        lastError = nil

        do {
            let existing: String?
            let write: (String) async throws -> Void

            if config.mode == .remote {
                guard let client = await remoteClient(for: config) else { return }
                existing = try await client.read(config.normalizedNotePath)
                write = { content in
                    try await client.write(config.normalizedNotePath, content: content)
                }
            } else {
                guard let noteURL = config.noteURL, let vault = config.vaultURL else {
                    lastError = "Choose a valid Obsidian vault folder."
                    return
                }
                guard FileManager.default.fileExists(atPath: vault.path) else {
                    lastError = "The Obsidian vault folder no longer exists."
                    return
                }
                try FileManager.default.createDirectory(
                    at: noteURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                existing = try? String(contentsOf: noteURL, encoding: .utf8)
                write = { content in
                    try content.write(to: noteURL, atomically: true, encoding: .utf8)
                }
            }

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
                try await write(rendered)
            }
            lastWrittenContent = rendered
            try await exportArchive(config: config, items: all)
            lastSyncAt = clock()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Archive

    /// Writes every task, project, contact and day as its own note. Only
    /// changed files are written; only files this exporter created are
    /// ever removed.
    private func exportArchive(config: ObsidianSettings, items: [WorkItem]) async throws {
        let fingerprint = await archiveChangeFingerprint(items: items)
        let now = clock()
        if fingerprint == archiveFingerprint,
           let last = archiveExportedAt, now.timeIntervalSince(last) < 300
        {
            return
        }

        let root = ObsidianArchive.root(forNotePath: config.normalizedNotePath)
        let target = config.mode == .remote
            ? "remote|\(config.sanitizedRemoteHost):\(config.remotePort)|\(root)"
            : "local|\(config.vaultURL?.path ?? "")|\(root)"
        var manifest = await loadManifest()
        let isFresh = manifest?.target != target
        if isFresh { manifest = ObsidianArchiveManifest(target: target) }
        guard var manifest else { return }

        let snapshot = await archiveSnapshot(items: items)
        let calendar = calendar.calendar
        let rendered = await Task.detached(priority: .utility) {
            ObsidianArchive.render(snapshot, root: root, calendar: calendar)
        }.value
        var plan = manifest.plan(for: rendered)

        let io: ArchiveIO
        if config.mode == .remote {
            guard let client = await remoteClient(for: config) else { return }
            io = .remote(client)
        } else {
            guard let vault = config.vaultURL else { return }
            io = .local(vault)
            // Notes removed by hand in Obsidian are written again.
            let unchanged = rendered.keys.filter { manifest.files[$0] != nil && !plan.writes.contains($0) }
            let missing = await Task.detached(priority: .utility) {
                unchanged.filter {
                    !FileManager.default.fileExists(atPath: vault.appendingPathComponent($0).path)
                }
            }.value
            plan.writes.append(contentsOf: missing)
        }

        if isFresh {
            await removeLegacyNotes(io: io, knownIds: Set((snapshot.items + snapshot.deletedItems).map(\.id.description)))
        }

        var written = 0
        for path in plan.writes {
            guard let content = rendered[path] else { continue }
            try await io.write(path, content)
            manifest.files[path] = ObsidianArchiveManifest.hash(content)
            written += 1
            if written % 200 == 0 { await saveManifest(manifest) }
        }
        for path in plan.deletes {
            try? await io.delete(path)
            manifest.files[path] = nil
        }
        if !plan.writes.isEmpty || !plan.deletes.isEmpty || isFresh {
            await saveManifest(manifest)
        }
        archiveNoteCount = rendered.count
        archiveFingerprint = fingerprint
        archiveExportedAt = now
    }

    /// Notes from the old per-item snapshots (`TodayFlow/Tasks/<id>.md`).
    private func removeLegacyNotes(io: ArchiveIO, knownIds: Set<String>) async {
        for folder in ["TodayFlow/Tasks", "TodayFlow/Projects"] {
            guard let names = try? await io.list(folder) else { continue }
            for name in names where name.hasSuffix(".md") {
                let id = String(name.dropLast(3))
                guard knownIds.contains(id) else { continue }
                try? await io.delete("\(folder)/\(name)")
            }
        }
    }

    private func archiveSnapshot(items: [WorkItem]? = nil) async -> ObsidianArchiveSnapshot {
        let live: [WorkItem]
        if let items { live = items } else { live = await workItems.allItems() }
        let deleted = await workItems.deletedItems()
        let people = await contacts?.contacts() ?? []
        var contactTaskIds: [UUIDv7: [UUIDv7]] = [:]
        if let contacts {
            for person in people {
                let ids = await contacts.taskIds(forContact: person.id)
                if !ids.isEmpty { contactTaskIds[person.id] = ids }
            }
        }
        var snapshot = ObsidianArchiveSnapshot(
            items: live,
            deletedItems: deleted,
            events: await activities?.allEvents() ?? [],
            links: await links?.allLinks() ?? [],
            contacts: people,
            contactTaskIds: contactTaskIds,
            groups: await contacts?.groups() ?? [],
            memberships: await contacts?.groupMemberships() ?? [:],
            attachments: await attachments?.allAttachments() ?? []
        )
        for bundleId in snapshot.sourceAppIds {
            if let name = Self.appName(bundleId) { snapshot.appNames[bundleId] = name }
        }
        return snapshot
    }

    private static var appNameCache: [String: String?] = [:]

    /// The installed app's display name for a bundle id ("Google Chrome").
    private static func appName(_ bundleId: String) -> String? {
        if let cached = appNameCache[bundleId] { return cached }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .map { FileManager.default.displayName(atPath: $0.path) }
            .map { $0.hasSuffix(".app") ? String($0.dropLast(4)) : $0 }
        appNameCache[bundleId] = .some(name)
        return name
    }

    /// Cheap signature of everything the archive shows; the full export
    /// runs only when it changes (or every five minutes as a safety net).
    private func archiveChangeFingerprint(items: [WorkItem]) async -> String {
        var parts: [String] = []
        parts.append(items.map { "\($0.id):\($0.version)" }.joined(separator: ","))
        parts.append((await workItems.deletedItems()).map { "\($0.id):\($0.version)" }.joined(separator: ","))
        parts.append(await activities?.recent(limit: 1).first?.id.description ?? "")
        parts.append((await links?.allLinks() ?? []).map(\.id.description).joined(separator: ","))
        parts.append((await contacts?.contacts() ?? []).map { "\($0.id):\($0.version)" }.joined(separator: ","))
        parts.append((await attachments?.allAttachments() ?? []).map { "\($0.id):\($0.version)" }.joined(separator: ","))
        return ObsidianArchiveManifest.hash(parts.joined(separator: "|"))
    }

    private func loadManifest() async -> ObsidianArchiveManifest? {
        guard let raw = await settings.value(for: SettingKeys.obsidianArchive),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(ObsidianArchiveManifest.self, from: data)
    }

    private func saveManifest(_ manifest: ObsidianArchiveManifest) async {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? await settings.set(String(decoding: data, as: UTF8.self), for: SettingKeys.obsidianArchive)
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

    private func remoteClient(
        for config: ObsidianSettings
    ) async -> (any ObsidianRemoteTransport)? {
        guard config.mode == .remote else { return nil }
        guard let key = await keychain.read(KeychainKeys.obsidianAPIKey),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            lastError = "Paste the Obsidian API key in Settings → Obsidian."
            return nil
        }
        switch config.remoteTransport {
        case .rest:
            guard let client = ObsidianRemoteClient(settings: config, apiKey: key) else {
                lastError = "The remote Obsidian address is invalid."
                return nil
            }
            return client
        case .mcp:
            guard let client = ObsidianMCPClient(settings: config, apiKey: key) else {
                lastError = "The remote Obsidian address is invalid."
                return nil
            }
            return client
        }
    }
}

/// Where archive files go: a vault folder on this Mac or a remote server.
private enum ArchiveIO {
    case local(URL)
    case remote(any ObsidianRemoteTransport)

    func write(_ path: String, _ content: String) async throws {
        switch self {
        case .local(let vault):
            let url = vault.appendingPathComponent(path)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try content.write(to: url, atomically: true, encoding: .utf8)
            }.value
        case .remote(let client):
            try await client.write(path, content: content)
        }
    }

    func delete(_ path: String) async throws {
        switch self {
        case .local(let vault):
            let url = vault.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        case .remote(let client):
            try await client.delete(path)
        }
    }

    /// File names in one folder (folders end with "/").
    func list(_ folder: String) async throws -> [String] {
        switch self {
        case .local(let vault):
            let url = vault.appendingPathComponent(folder)
            return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        case .remote(let client):
            return try await client.list(folder)
                .map { $0.split(separator: "/").last.map(String.init) ?? $0 }
        }
    }
}
