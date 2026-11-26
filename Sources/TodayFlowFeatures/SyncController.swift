#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import Foundation
import GRDB
import Observation
import TodayFlowCore
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
        var details = ["Server: \(snapshot.serverAddress)"]
        if let user = snapshot.userName { details.append("User: \(user)") }
        details.append("This \(Self.deviceKind): \(snapshot.deviceName)")
        if snapshot.pendingCount > 0 { details.append("Changes waiting to send: \(snapshot.pendingCount)") }
        if let checked = snapshot.lastCheckedAt {
            details.append("Last checked \(checked.formatted(date: .omitted, time: .standard))")
        }
        return SyncBadgeStatus(state: state, lastSyncAt: snapshot.lastSyncAt, details: details, log: snapshot.log)
    }

    struct Config: Codable, Equatable {
        var server: String
        var deviceId: String
        var deviceName: String
        /// The server user; nil for pairings made before servers sent it.
        var userName: String?
        var enabled: Bool
        var pairedAt: Date
        var lastSyncAt: Date?
    }

    static let settingKey = SettingKeys.sync
    static let tokenKey = KeychainKeys.syncDeviceToken
    static let interval: Duration = .seconds(10)

    /// `Application Support/TodayFlow/Attachments`, where both apps keep files
    /// (the Mac's `AppEnvironment.defaultAttachmentsDirectory()`).
    public nonisolated static func defaultFilesDirectory() -> URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("TodayFlow", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    #if os(macOS)
    static let deviceKind = "Mac"
    static var deviceName: String { Host.current().localizedName ?? "Mac" }
    #else
    static let deviceKind = "iPhone"
    static var deviceName: String { UIDevice.current.name }
    #endif

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
        filesDirectory: URL = SyncController.defaultFilesDirectory(),
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
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        let wake = NSWorkspace.didWakeNotification
        #else
        let center = NotificationCenter.default
        let wake = UIApplication.willEnterForegroundNotification
        #endif
        wakeObserver = center.addObserver(forName: wake, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.runRound() }
        }
        if config?.enabled == true { startLoop() }
        Task { await fetchUserNameIfMissing() }
    }

    // MARK: - SyncPanelBackend

    /// Asks the server for the user's name once, for pairings made before
    /// the server sent it. Quietly does nothing when offline.
    private func fetchUserNameIfMissing() async {
        guard var config, config.userName == nil, let url = URL(string: config.server),
              let token = await keychain.read(Self.tokenKey),
              let status = try? await SyncClient(baseURL: url, token: token, session: session).status(),
              let name = status.userName
        else { return }
        config.userName = name
        try? await save(config)
        await refresh()
    }

    public func refresh() async {
        var next = SyncSnapshot()
        if let config {
            next.isPaired = true
            next.serverAddress = config.server
            next.userName = config.userName
            next.deviceName = config.deviceName
            next.isEnabled = config.enabled
            next.lastSyncAt = config.lastSyncAt
        }
        next.isSyncing = snapshot.isSyncing
        next.log = snapshot.log
        next.lastCheckedAt = snapshot.lastCheckedAt
        next.lastError = snapshot.lastError
        next.lastResult = snapshot.lastResult
        next.pendingCount = (try? await store.pendingCount()) ?? 0
        next.skippedFiles = ((try? await store.skippedBlobs()) ?? []).map { "\($0.name): \($0.reason)" }
        snapshot = next
    }

    public func pair(server: String, code: String) async -> String? {
        do {
            let url = try SyncClient.serverURL(from: server)
            let deviceName = Self.deviceName
            let paired = try await SyncClient(baseURL: url, token: nil, session: session)
                .pair(code: code.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: deviceName)
            // Before anything leaves or arrives: a copy of this Mac's data.
            try await backupBeforeFirstSync()
            try await store.markAllPending()
            try await store.resetCursor()
            try await keychain.write(paired.token, for: Self.tokenKey)
            let config = Config(
                server: url.absoluteString, deviceId: paired.deviceId, deviceName: deviceName,
                userName: paired.userName, enabled: false, pairedAt: .now, lastSyncAt: nil
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
            snapshot.lastCheckedAt = .now
            record(report)
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
            if self.config?.userName == nil { await fetchUserNameIfMissing() }
        } catch SyncError.signedOut {
            config.enabled = false
            try? await save(config)
            stopLoop()
            snapshot.lastError = SyncError.signedOut.errorDescription
            recordError(SyncError.signedOut.errorDescription ?? "Signed out")
        } catch {
            snapshot.lastError = Self.message(for: error)
            recordError(Self.message(for: error))
        }
        await refresh()
    }

    // MARK: - Log

    /// Adds a round that moved something to the log and the log file.
    private func record(_ report: SyncRunner.Report) {
        let activity = report.historyEntries
        guard report.received + report.sent + report.filesUploaded + report.filesDownloaded + report.filesRemoved > 0
        else { return }
        var parts: [String] = []
        if report.sent > 0 { parts.append("sent \(report.sent)") }
        if report.received > 0 { parts.append("received \(report.received)") }
        if report.filesUploaded > 0 { parts.append("\(report.filesUploaded) file(s) up") }
        if report.filesDownloaded > 0 { parts.append("\(report.filesDownloaded) file(s) down") }
        if report.filesRemoved > 0 { parts.append("\(report.filesRemoved) old download(s) removed") }
        let summary = parts.joined(separator: ", ").capitalizedFirst
        var details = report.events.map { event -> String in
            switch event.kind {
            case .sent: return "Sent \(event.text)"
            case .received: return "Received \(event.text)"
            case .fileUploaded: return "Uploaded \(event.text)"
            case .fileDownloaded: return "Downloaded \(event.text)"
            }
        }
        if report.unlisted > 0 { details.append("…and \(report.unlisted) more") }
        if activity > 0 { details.append("\(activity) history entr\(activity == 1 ? "y" : "ies") (who changed what, when)") }
        append(SyncLogEntry(time: .now, summary: summary, details: details))
        Diagnostics.log("sync", summary + (details.isEmpty ? "" : ": " + details.joined(separator: "; ")))
    }

    /// Logs an error once until it changes or a round succeeds.
    private func recordError(_ message: String) {
        if let last = snapshot.log.first, last.isError, last.summary == message { return }
        append(SyncLogEntry(time: .now, summary: message, isError: true))
        Diagnostics.log("sync", "error: \(message)")
    }

    private func append(_ entry: SyncLogEntry) {
        snapshot.log.insert(entry, at: 0)
        if snapshot.log.count > 150 { snapshot.log.removeLast(snapshot.log.count - 150) }
    }

    /// Views that do not observe the database reload on these.
    private static func announceRemoteChanges() {
        for name in [
            TodayFlowEvents.itemsChanged,
            TodayFlowEvents.attachmentsChanged,
            TodayFlowEvents.remindersChanged,
            TodayFlowEvents.remoteTraysChanged,
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

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
