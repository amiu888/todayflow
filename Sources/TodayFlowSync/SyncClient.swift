import CryptoKit
import Foundation
import TodayFlowPersistence

/// Why a sync call failed, in words for the Settings tab.
public enum SyncError: Error, Equatable, LocalizedError {
    case invalidAddress(String)
    /// The server no longer accepts this Mac's token.
    case signedOut
    case wrongPairingCode
    case tooManyAttempts
    case server(status: Int, message: String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .invalidAddress(let reason): return reason
        case .signedOut: return "This Mac was signed out of the server. Pair it again."
        case .wrongPairingCode: return "That pairing code is wrong or was replaced."
        case .tooManyAttempts: return "Too many wrong codes. Wait 10 minutes and try again."
        case .server(let status, let message):
            return message.isEmpty ? "The server answered \(status)." : message
        case .network(let message): return "Can't reach the server: \(message)"
        }
    }
}

/// The calls a sync round makes; the server, or a fake in tests.
public protocol SyncTransport: Sendable {
    func pull(since: Int64, limit: Int) async throws -> SyncClient.PullPage
    func push(_ changes: [SyncChange]) async throws -> [SyncClient.PushResult]
    /// True when this user's server already has the file.
    func hasBlob(_ sha256: String) async throws -> Bool
    /// Uploads a file straight from disk.
    func putBlob(file: URL, sha256: String) async throws
    /// Downloads to `destination`; false when the server doesn't have it (yet).
    func getBlob(_ sha256: String, to destination: URL) async throws -> Bool
}

/// HTTP client for the TodayFlow Sync Server (`Server/README.md`).
public struct SyncClient: SyncTransport {
    public let baseURL: URL
    public let token: String?
    private let session: URLSession

    public init(baseURL: URL, token: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Checks and normalizes a typed server address. Plain `http://` is
    /// allowed only for this Mac and private home-network addresses.
    public static func serverURL(from text: String) throws -> URL {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { throw SyncError.invalidAddress("Enter the server address.") }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { throw SyncError.invalidAddress("That isn't a server address. Example: http://nas.local:8787") }
        if scheme == "http" && !isPrivate(host: host) {
            throw SyncError.invalidAddress(
                "Use https:// for a server outside your home network. Plain http:// is only for home addresses such as nas.local."
            )
        }
        return url
    }

    static func isPrivate(host: String) -> Bool {
        let host = host.lowercased()
        if host == "localhost" || host.hasSuffix(".local") || !host.contains(".") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        case (100, 64...127): return true // Tailscale
        default: return false
        }
    }

    // MARK: - Calls

    public struct PairResponse: Decodable, Sendable {
        public var deviceId: String
        public var token: String
    }

    public struct Status: Decodable, Sendable {
        public var userId: String
        public var records: Int64
        public var deviceId: String
    }

    public struct PushResult: Decodable, Sendable {
        public var entity: String
        public var id: String
        public var status: String
        public var current: SyncChange?

        public init(entity: String, id: String, status: String, current: SyncChange?) {
            self.entity = entity
            self.id = id
            self.status = status
            self.current = current
        }
    }

    public struct PullPage: Decodable, Sendable {
        public var changes: [SyncChange]
        public var next: Int64
        public var more: Bool

        public init(changes: [SyncChange], next: Int64, more: Bool) {
            self.changes = changes
            self.next = next
            self.more = more
        }
    }

    public func pair(code: String, deviceName: String) async throws -> PairResponse {
        struct Body: Encodable { var pairingCode: String; var deviceName: String }
        do {
            return try await send("v1/pair", method: "POST", body: Body(pairingCode: code, deviceName: deviceName))
        } catch SyncError.signedOut {
            throw SyncError.wrongPairingCode
        }
    }

    public func status() async throws -> Status {
        try await send("v1/status", method: "GET", body: Optional<String>.none)
    }

    public func push(_ changes: [SyncChange]) async throws -> [PushResult] {
        struct Body: Encodable { var changes: [SyncChange] }
        struct Response: Decodable { var results: [PushResult] }
        let response: Response = try await send("v1/push", method: "POST", body: Body(changes: changes))
        return response.results
    }

    public func pull(since: Int64, limit: Int = 500) async throws -> PullPage {
        try await send("v1/pull?since=\(since)&limit=\(limit)", method: "GET", body: Optional<String>.none)
    }

    // MARK: - Files

    public func hasBlob(_ sha256: String) async throws -> Bool {
        let (_, status) = try await raw("v1/blobs/\(sha256)", method: "HEAD", body: nil)
        switch status {
        case 200: return true
        case 404: return false
        case 401: throw SyncError.signedOut
        default: throw SyncError.server(status: status, message: "")
        }
    }

    public func putBlob(file: URL, sha256: String) async throws {
        var request = try blobRequest(sha256, method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (body, response): (Data, URLResponse)
        do {
            (body, response) = try await session.upload(for: request, fromFile: file)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return
        case 401: throw SyncError.signedOut
        default:
            let message = (try? JSONDecoder().decode(Problem.self, from: body))?.error.message ?? ""
            throw SyncError.server(status: status, message: message)
        }
    }

    public func getBlob(_ sha256: String, to destination: URL) async throws -> Bool {
        let request = try blobRequest(sha256, method: "GET")
        let (temporary, response): (URL, URLResponse)
        do {
            (temporary, response) = try await session.download(for: request)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return true
        case 404: return false
        case 401: throw SyncError.signedOut
        case let status: throw SyncError.server(status: status, message: "")
        }
    }

    private func blobRequest(_ sha256: String, method: String) throws -> URLRequest {
        guard let url = URL(string: "v1/blobs/\(sha256)", relativeTo: baseURL.appendingPathComponent("")) else {
            throw SyncError.invalidAddress("Bad server address.")
        }
        // Files can be up to 1 GB.
        var request = URLRequest(url: url, timeoutInterval: 3600)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func raw(_ path: String, method: String, body: Data?) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("")) else {
            throw SyncError.invalidAddress("Bad server address.")
        }
        // Files can be up to 200 MB.
        var request = URLRequest(url: url, timeoutInterval: 600)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
    }

    /// Hummingbird's error body: `{"error": {"message": "…"}}`.
    private struct Problem: Decodable {
        struct Inner: Decodable { var message: String }
        var error: Inner
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ path: String, method: String, body: Body?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("")) else {
            throw SyncError.invalidAddress("Bad server address.")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw SyncError.server(status: status, message: "The server sent an answer this app doesn't understand. Is the address a TodayFlow server?")
            }
        case 401: throw SyncError.signedOut
        case 429: throw SyncError.tooManyAttempts
        default:
            let message = (try? JSONDecoder().decode(Problem.self, from: data))?.error.message
                ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw SyncError.server(status: status, message: message)
        }
    }
}

/// One sync round: pull everything new, then push everything pending.
public struct SyncRunner: Sendable {
    public let store: SyncStore
    public let client: any SyncTransport
    /// Where downloaded attachment files go; nil syncs rows only.
    public let filesDirectory: URL?
    /// Tests on one Mac turn this off to act like a second Mac that can't
    /// see the first one's files.
    var useOriginalPaths = true
    /// The server's per-file limit.
    public static let maxFileBytes = 1024 * 1_048_576
    /// Files up to this size download in every round; bigger ones when opened.
    public static let autoDownloadBytes = 10 * 1_048_576
    /// Downloaded copies younger than this are never cleaned up.
    var downloadGrace: TimeInterval = 600

    public init(store: SyncStore, client: any SyncTransport, filesDirectory: URL? = nil) {
        self.store = store
        self.client = client
        self.filesDirectory = filesDirectory
    }

    public struct Report: Sendable, Equatable {
        /// Local rows changed by changes from other Macs.
        public var received = 0
        /// Local changes the server accepted.
        public var sent = 0
        public var filesUploaded = 0
        public var filesDownloaded = 0
        /// Files that failed this round and will be retried.
        public var fileErrors = 0
        /// Downloaded copies deleted because their attachment is gone.
        public var filesRemoved = 0

        public init() {}
    }

    public func run() async throws -> Report {
        var report = Report()
        // Pull first so a stale local edit never overwrites a newer remote one.
        var cursor = try await store.cursor()
        while true {
            let page = try await client.pull(since: cursor, limit: 500)
            report.received += try await store.apply(page.changes, cursor: page.next)
            cursor = page.next
            if !page.more { break }
        }
        if let filesDirectory {
            report.filesRemoved = (try? await removeUnusedDownloads(in: filesDirectory)) ?? 0
            try await downloadFiles(into: filesDirectory, report: &report)
            try await uploadFiles(report: &report)
        }
        // The server refuses changes dated in the future.
        try await store.clampFutureChanges()
        // Push in batches. A row edited during the push stays pending for the
        // next round, so a busy Mac never loops forever.
        for _ in 0..<500 {
            let pending = try await store.pendingChanges(limit: 200)
            if pending.isEmpty { break }
            let results = try await client.push(pending)
            var accepted: [SyncChange] = []
            var newer: [SyncChange] = []
            for (change, result) in zip(pending, results) {
                if result.status == "accepted" {
                    accepted.append(change)
                } else if let current = result.current {
                    newer.append(current)
                } else {
                    accepted.append(change)
                }
            }
            try await store.markPushed(accepted)
            if !newer.isEmpty { report.received += try await store.apply(newer) }
            report.sent += accepted.count
            if pending.count < 200 { break }
        }
        return report
    }

    // MARK: - Files

    /// Fetches small files this Mac doesn't have; bigger ones wait until
    /// they are opened (`fetchFile`). One bad file never stops the round.
    private func downloadFiles(into directory: URL, report: inout Report) async throws {
        for file in try await store.attachmentsWithBlob()
        where !(useOriginalPaths ? file.hasLocalBytes : file.hasOwnCopy) && (file.blobSize ?? 0) <= Self.autoDownloadBytes {
            do {
                if try await download(file, into: directory) != nil { report.filesDownloaded += 1 }
            } catch let error as SyncError where Self.stopsRound(error) {
                throw error
            } catch {
                report.fileErrors += 1
            }
        }
    }

    /// Downloads one attachment's file now (opening a big file). Returns
    /// where it is, or nil when the server doesn't have it yet.
    public func fetchFile(attachmentId: String) async throws -> URL? {
        guard let directory = filesDirectory,
              let file = try await store.attachmentsWithBlob().first(where: { $0.id == attachmentId })
        else { return nil }
        if file.hasOwnCopy, let copy = file.localCopyPath { return URL(fileURLWithPath: copy) }
        return try await download(file, into: directory)
    }

    private func download(_ file: SyncAttachmentFile, into directory: URL) async throws -> URL? {
        guard let sha = file.blobSHA256 else { return nil }
        let folder = directory.appendingPathComponent("Synced", isDirectory: true)
            .appendingPathComponent(sha, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(Self.fileName(for: file))
        let partial = folder.appendingPathComponent(".download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: partial) }
        guard try await client.getBlob(sha, to: partial) else { return nil } // not uploaded yet
        guard try Self.sha256(file: partial) == sha else { throw SyncError.server(status: 200, message: "A downloaded file was damaged.") }
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: partial, to: target)
        try await store.setLocalCopy(attachmentId: file.id, path: target.path)
        return target
    }

    /// Deletes downloaded copies no live attachment uses any more. Only
    /// `Synced/` is touched; recent folders are left alone so a download in
    /// progress is never removed.
    func removeUnusedDownloads(in directory: URL) async throws -> Int {
        let synced = directory.appendingPathComponent("Synced", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: synced, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return 0 }
        let used = Set(try await store.attachmentsWithBlob().compactMap(\.blobSHA256))
        let cutoff = Date().addingTimeInterval(-downloadGrace)
        var removed = 0
        for folder in folders where !used.contains(folder.lastPathComponent) {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified > cutoff { continue }
            if (try? FileManager.default.removeItem(at: folder)) != nil { removed += 1 }
        }
        return removed
    }

    /// Uploads files of attachments made on this Mac, straight from disk,
    /// then records their hash on the row (pushed right after).
    private func uploadFiles(report: inout Report) async throws {
        for file in try await store.attachmentsWithoutBlob() {
            guard let url = file.localFile else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > Self.maxFileBytes {
                try await store.skipBlob(attachmentId: file.id, reason: "Larger than 1 GB", fileSize: size)
                continue
            }
            do {
                let sha = try Self.sha256(file: url)
                if try await !client.hasBlob(sha) {
                    try await client.putBlob(file: url, sha256: sha)
                }
                try await store.setBlob(attachmentId: file.id, sha256: sha, size: size)
                report.filesUploaded += 1
            } catch let error as SyncError where Self.stopsRound(error) {
                throw error
            } catch let error as CocoaError where error.code == .fileReadNoPermission {
                try await store.skipBlob(attachmentId: file.id, reason: "macOS won't let TodayFlow read it", fileSize: size)
            } catch {
                report.fileErrors += 1
            }
        }
    }

    private static func stopsRound(_ error: SyncError) -> Bool {
        switch error {
        case .signedOut, .network: return true
        default: return false
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes a file in 1 MB pieces, so a large video never fills memory.
    static func sha256(file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The display name, with the original file's extension when the name
    /// has none ("Pasted image" → "Pasted image.png"), so the file opens.
    static func fileName(for file: SyncAttachmentFile) -> String {
        let name = safeFileName(file.displayName)
        let original = URL(fileURLWithPath: file.reference).pathExtension
        if URL(fileURLWithPath: name).pathExtension.isEmpty, !original.isEmpty {
            return name + "." + original
        }
        return name
    }

    /// The attachment's name as a file name: no folders, never empty.
    static func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = cleaned.hasPrefix(".") ? "file" + cleaned : cleaned
        return trimmed.isEmpty ? "file" : String(trimmed.prefix(200))
    }
}
