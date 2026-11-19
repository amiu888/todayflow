import AppKit
import Foundation
import GRDB
import Observation
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowPersistence
import TodayFlowSync

/// Runs sync with the TodayFlow server and backs Settings ▸ Sync.
///
/// Sync is off until the user pairs and turns it on. While on, a round runs
/// at once, then every 10 seconds, on wake from sleep, and on "Sync Now".
@MainActor
@Observable
public final class SyncController: SyncPanelBackend {
    public private(set) var snapshot = SyncSnapshot() {
        didSet { if snapshot != oldValue { onStatusChange?(badgeStatus) } }
    }
    /// Called when the header badge should change.
    @ObservationIgnored public var onStatusChange: (@MainActor (SyncBadgeStatus?) -> Void)?

    /// The header badge: hidden until paired. A background round only shows
    /// "syncing" when it has something to send, so the dot doesn't blink
    /// every 10 seconds.
    public var badgeStatus: SyncBadgeStatus? {
        guard snapshot.isPaired else { return nil }
        let state: SyncBadgeState
        if !snapshot.isEnabled {
            state = .off
        } else if snapshot.isSyncing && snapshot.pendingCount > 0 {
            state = .syncing
        } else if let error = snapshot.lastError {
            state = .failed(error)
        } else if snapshot.pendingCount > 0 || snapshot.lastSyncAt == nil {
            state = .waiting(snapshot.pendingCount)
        } else {
            state = .synced
        }
        return SyncBadgeStatus(state: state, lastSyncAt: snapshot.lastSyncAt)
    }

    struct Config: Codable, Equatable {
        var server: String
        var deviceId: String
        var deviceName: String
        var enabled: Bool
        var pairedAt: Date
        var lastSyncAt: Date?
    }

    static let settingKey = "sync"
    static let tokenKey = "sync_device_token"
    static let interval: Duration = .seconds(10)

    @ObservationIgnored private let queue: DatabaseQueue
    @ObservationIgnored private let databaseURL: URL?
    @ObservationIgnored private let settings: any SettingRepository
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private let store: SyncStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let filesDirectory: URL
    @ObservationIgnored private var config: Config?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    public init(
        queue: DatabaseQueue,
        databaseURL: URL?,
        settings: any SettingRepository,
        keychain: any KeychainStore,
        filesDirectory: URL = AppEnvironment.defaultAttachmentsDirectory(),
        session: URLSession = .shared
    ) {
        self.filesDirectory = filesDirectory
        self.queue = queue
        self.databaseURL = databaseURL
        self.settings = settings
        self.keychain = keychain
        self.store = SyncStore(queue: queue)
        self.session = session
    }

    /// Loads the saved pairing and starts syncing if it was on.
    public func start() async {
        config = await loadConfig()
        await refresh()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.runRound() }
        }
        if config?.enabled == true { startLoop() }
    }

    // MARK: - SyncPanelBackend

    public func refresh() async {
        var next = SyncSnapshot()
        if let config {
            next.isPaired = true
            next.serverAddress = config.server
            next.deviceName = config.deviceName
            next.isEnabled = config.enabled
            next.lastSyncAt = config.lastSyncAt
        }
        next.isSyncing = snapshot.isSyncing
        next.lastError = snapshot.lastError
        next.lastResult = snapshot.lastResult
        next.pendingCount = (try? await store.pendingCount()) ?? 0
        next.skippedFiles = ((try? await store.skippedBlobs()) ?? []).map { "\($0.name): \($0.reason)" }
        snapshot = next
    }

    public func pair(server: String, code: String) async -> String? {
        do {
            let url = try SyncClient.serverURL(from: server)
            let deviceName = Host.current().localizedName ?? "Mac"
            let paired = try await SyncClient(baseURL: url, token: nil, session: session)
                .pair(code: code.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: deviceName)
            // Before anything leaves or arrives: a copy of this Mac's data.
            try await backupBeforeFirstSync()
            try await store.markAllPending()
            try await store.resetCursor()
            try await keychain.write(paired.token, for: Self.tokenKey)
            let config = Config(
                server: url.absoluteString, deviceId: paired.deviceId, deviceName: deviceName,
                enabled: false, pairedAt: .now, lastSyncAt: nil
            )
            try await save(config)
            snapshot.lastError = nil
            snapshot.lastResult = nil
            await refresh()
            return nil
        } catch {
            return Self.message(for: error)
        }
    }

    public func unpair() async {
        stopLoop()
        try? await keychain.delete(Self.tokenKey)
        try? await settings.remove(Self.settingKey)
        config = nil
        snapshot.lastError = nil
        snapshot.lastResult = nil
        await refresh()
    }

    public func setEnabled(_ enabled: Bool) async {
        guard var config else { return }
        config.enabled = enabled
        try? await save(config)
        if enabled {
            snapshot.lastError = nil
            startLoop()
        } else {
            stopLoop()
        }
        await refresh()
    }

    /// Downloads a file that is only on the server (a big file, fetched when
    /// opened). Returns the attachment pointing at the new copy.
    public func fetchFile(for attachment: Attachment) async -> Attachment? {
        guard let config, let url = URL(string: config.server),
              let token = await keychain.read(Self.tokenKey)
        else { return nil }
        let runner = SyncRunner(
            store: store,
            client: SyncClient(baseURL: url, token: token, session: session),
            filesDirectory: filesDirectory
        )
        guard let file = try? await runner.fetchFile(attachmentId: attachment.id.description) else { return nil }
        var updated = attachment
        updated.localCopyPath = file.path
        return updated
    }

    public func syncNow() async {
        await runRound()
    }

    // MARK: - Rounds

    private func startLoop() {
        loop?.cancel()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.runRound()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }

    private func runRound() async {
        guard var config, config.enabled, !snapshot.isSyncing,
              let url = URL(string: config.server)
        else { return }
        guard let token = await keychain.read(Self.tokenKey) else {
            snapshot.lastError = "This Mac's sign-in for the server is missing. Unpair and pair again."
            return
        }
        snapshot.isSyncing = true
        defer { snapshot.isSyncing = false }
        let runner = SyncRunner(
            store: store,
            client: SyncClient(baseURL: url, token: token, session: session),
            filesDirectory: filesDirectory
        )
        do {
            let report = try await runner.run()
            config.lastSyncAt = .now
            try? await save(config)
            snapshot.lastError = nil
            let busy = report.received + report.sent + report.filesUploaded + report.filesDownloaded > 0
            if busy || snapshot.lastResult == nil {
                var text = "Received \(report.received), sent \(report.sent)"
                if report.filesUploaded + report.filesDownloaded > 0 {
                    text += "; files: \(report.filesUploaded) up, \(report.filesDownloaded) down"
                }
                snapshot.lastResult = text
            }
            snapshot.lastError = report.fileErrors > 0
                ? "\(report.fileErrors) file(s) couldn't be synced; trying again next round."
                : nil
            if report.received > 0 || report.filesDownloaded > 0 { Self.announceRemoteChanges() }
        } catch SyncError.signedOut {
            config.enabled = false
            try? await save(config)
            stopLoop()
            snapshot.lastError = SyncError.signedOut.errorDescription
        } catch {
            snapshot.lastError = Self.message(for: error)
        }
        await refresh()
    }

    /// Views that do not observe the database reload on these.
    private static func announceRemoteChanges() {
        for name in [
            TodayFlowEvents.itemsChanged,
            TodayFlowEvents.attachmentsChanged,
            TodayFlowEvents.remindersChanged,
        ] {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }

    // MARK: - Storage

    private func loadConfig() async -> Config? {
        guard let json = await settings.value(for: Self.settingKey) else { return nil }
        return try? Self.decoder.decode(Config.self, from: Data(json.utf8))
    }

    private func save(_ config: Config) async throws {
        let data = try Self.encoder.encode(config)
        try await settings.set(String(decoding: data, as: UTF8.self), for: Self.settingKey)
        self.config = config
    }

    private func backupBeforeFirstSync() async throws {
        guard let databaseURL else { return }
        let directory = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = directory.appendingPathComponent("before-sync-\(formatter.string(from: .now)).sqlite")
        try await queue.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [file.path])
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
