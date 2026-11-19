import Foundation
import Hummingbird
import Logging
import NIOCore
import NIOSSL
import PostgresNIO

/// Counts failed pairing attempts. After `limit` failures inside `window`,
/// pairing is refused for everyone until the window passes. Pairing is rare,
/// so a lock-out costs little, while guessing a 96-bit code becomes hopeless.
public actor PairingLimiter {
    let limit: Int
    let window: TimeInterval
    private var failures: [Date] = []

    public init(limit: Int = 10, window: TimeInterval = 10 * 60) {
        self.limit = limit
        self.window = window
    }

    func isLocked(now: Date) -> Bool {
        failures.removeAll { now.timeIntervalSince($0) > window }
        return failures.count >= limit
    }

    func recordFailure(now: Date) {
        failures.append(now)
    }
}

public struct ServerConfig: Sendable {
    public var maxChangesPerPush = 1000
    public var maxPullPage = 1000
    /// Largest push body. A row with an attachment bookmark is a few KB.
    public var maxPushBytes = 16 * 1024 * 1024
    /// Largest attachment file.
    /// Uploads stream to disk, so this is not bounded by memory.
    public var maxBlobBytes = 1024 * 1024 * 1024
    /// A change dated further ahead than this is refused: a device with a
    /// wrong clock would otherwise win every conflict.
    public var maxClockSkew: TimeInterval = 10 * 60
    /// Where attachment files live; nil turns the blob routes off.
    public var blobs: BlobStore?
    public var pairingLimiter = PairingLimiter()
    /// Delay after a wrong pairing code.
    public var wrongCodeDelay: Duration = .seconds(1)
    /// Injected for tests.
    public var now: @Sendable () -> Date = { Date() }

    public init(blobs: BlobStore? = nil) {
        self.blobs = blobs
    }
}

/// Builds the HTTP routes.
///
///     GET  /health             no sign-in; "ok"
///     POST /v1/pair            a user's pairing code → device id + token
///     GET  /v1/status          counts, for the app's settings screen
///     POST /v1/push            upload changes
///     GET  /v1/pull            ?since=N&limit=M → changes after N
///     PUT  /v1/blobs/{sha256}  upload an attachment file
///     HEAD /v1/blobs/{sha256}  200 when this user has it, 404 when not
///     GET  /v1/blobs/{sha256}  download it
///
/// Everything under /v1 except /pair needs `Authorization: Bearer <token>`.
/// The token decides the user; nothing in a request can name another user.
public func buildRouter(store: Store, config: ServerConfig) -> Router<BasicRequestContext> {
    let router = Router()
    router.get("health") { _, _ in "ok" }

    router.post("v1/pair") { request, context -> PairResponse in
        let body = try await request.decode(as: PairRequest.self, context: context)
        let limiter = config.pairingLimiter
        guard await !limiter.isLocked(now: config.now()) else {
            throw HTTPError(.tooManyRequests, message: "Too many wrong pairing codes. Try again in 10 minutes.")
        }
        guard let paired = try await store.pair(code: body.pairingCode, deviceName: body.deviceName) else {
            await limiter.recordFailure(now: config.now())
            try await Task.sleep(for: config.wrongCodeDelay)
            throw HTTPError(.unauthorized, message: "Wrong pairing code.")
        }
        return PairResponse(
            deviceId: paired.caller.deviceId,
            userName: try await store.userName(id: paired.caller.userId),
            token: paired.token
        )
    }

    @Sendable func caller(_ request: Request) async throws -> Store.Caller {
        guard let header = request.headers[.authorization],
              header.hasPrefix("Bearer "),
              let caller = try await store.caller(forToken: String(header.dropFirst(7)))
        else {
            throw HTTPError(.unauthorized, message: "Sign-in token missing, unknown, or revoked.")
        }
        return caller
    }

    router.get("v1/status") { request, _ -> StatusResponse in
        let caller = try await caller(request)
        let counts = try await store.counts(caller: caller)
        return StatusResponse(
            ok: true, userId: caller.userId, userName: try await store.userName(id: caller.userId),
            records: counts.records, latestSeq: counts.latestSeq, deviceId: caller.deviceId
        )
    }

    router.post("v1/push") { request, _ -> PushResponse in
        let caller = try await caller(request)
        let buffer = try await request.body.collect(upTo: config.maxPushBytes)
        let body: PushRequest
        do {
            body = try JSONDecoder().decode(PushRequest.self, from: Data(buffer: buffer))
        } catch {
            throw HTTPError(.badRequest, message: "Body is not a valid push request.")
        }
        guard body.changes.count <= config.maxChangesPerPush else {
            throw HTTPError(.contentTooLarge, message: "At most \(config.maxChangesPerPush) changes per push.")
        }
        let latestAllowed = config.now().addingTimeInterval(config.maxClockSkew)
        for change in body.changes {
            guard change.op == "upsert" || change.op == "delete" else {
                throw HTTPError(.badRequest, message: "Unknown op '\(change.op)'.")
            }
            guard !change.entity.isEmpty, !change.id.isEmpty,
                  change.entity.count <= 64, change.id.count <= 200
            else {
                throw HTTPError(.badRequest, message: "entity and id are required and must be short.")
            }
            guard change.op == "delete" || change.data != nil else {
                throw HTTPError(.badRequest, message: "An upsert needs data.")
            }
            guard let changedAt = parseTimestamp(change.changedAt) else {
                throw HTTPError(.badRequest, message: "changedAt must be an ISO 8601 UTC time.")
            }
            guard changedAt <= latestAllowed else {
                throw HTTPError(
                    .badRequest,
                    message: "A change is dated in the future (\(change.changedAt)). Check this device's clock."
                )
            }
        }
        return PushResponse(results: try await store.push(body.changes, caller: caller))
    }

    router.get("v1/pull") { request, _ -> PullResponse in
        let caller = try await caller(request)
        let since = request.uri.queryParameters["since"].flatMap { Int64($0) } ?? 0
        let asked = request.uri.queryParameters["limit"].flatMap { Int($0) } ?? 500
        let limit = min(max(asked, 1), config.maxPullPage)
        return try await store.pull(since: max(since, 0), limit: limit, caller: caller)
    }

    if let blobs = config.blobs {
        @Sendable func hash(_ context: BasicRequestContext) throws -> String {
            guard let hash = context.parameters.get("hash")?.lowercased(), BlobStore.isValidHash(hash) else {
                throw HTTPError(.badRequest, message: "Expected a SHA-256 hex hash.")
            }
            return hash
        }

        router.put("v1/blobs/:hash") { request, context -> Response in
            let caller = try await caller(request)
            let hash = try hash(context)
            let size: Int
            do {
                // Streamed to disk and always hashed, even when the file is
                // already stored: owning a hash requires proving you have it.
                size = try await blobs.put(streaming: request.body, hash: hash, maxBytes: config.maxBlobBytes)
            } catch BlobStore.StreamError.tooLarge {
                throw HTTPError(.contentTooLarge, message: "Files are limited to \(config.maxBlobBytes / 1_048_576) MB.")
            } catch BlobStore.PutError.hashMismatch {
                throw HTTPError(.badRequest, message: "The file does not match its hash.")
            }
            let created = try await store.claimBlob(sha256: hash, size: size, caller: caller)
            let reply = BlobResponse(sha256: hash, size: size, created: created)
            var response = try reply.response(from: request, context: context)
            response.status = created ? .created : .ok
            return response
        }

        router.head("v1/blobs/:hash") { request, context -> HTTPResponse.Status in
            let caller = try await caller(request)
            return try await store.ownsBlob(sha256: try hash(context), caller: caller) ? .ok : .notFound
        }

        router.get("v1/blobs/:hash") { request, context -> Response in
            let caller = try await caller(request)
            let hash = try hash(context)
            // Another user's file looks exactly like a missing one.
            guard try await store.ownsBlob(sha256: hash, caller: caller), let file = blobs.file(hash) else {
                throw HTTPError(.notFound, message: "No such file.")
            }
            // Streamed in 1 MB pieces, so a large file never fills memory.
            let url = file.url
            return Response(
                status: .ok,
                headers: [.contentType: "application/octet-stream"],
                body: ResponseBody(contentLength: file.size) { writer in
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                        try await writer.write(ByteBuffer(data: chunk))
                    }
                    try await writer.finish(nil)
                }
            )
        }
    }

    return router
}

/// Parses 2026-11-19T01:02:03Z or 2026-11-19T01:02:03.456Z.
public func parseTimestamp(_ text: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

/// Postgres connection settings from the environment. `PGSSLMODE=require`
/// encrypts the connection (use it when the database is on another machine);
/// inside one compose stack the default `disable` is fine.
public func postgresConfiguration(_ env: [String: String]) -> PostgresClient.Configuration {
    let tls: PostgresClient.Configuration.TLS
    switch env["PGSSLMODE"]?.lowercased() {
    case "require": tls = .require(.makeClientConfiguration())
    case "prefer": tls = .prefer(.makeClientConfiguration())
    default: tls = .disable
    }
    var config = PostgresClient.Configuration(
        host: env["PGHOST"] ?? "localhost",
        port: env["PGPORT"].flatMap { Int($0) } ?? 5432,
        username: env["PGUSER"] ?? "todayflow",
        password: env["PGPASSWORD"] ?? "",
        database: env["PGDATABASE"] ?? "todayflow",
        tls: tls
    )
    config.options.maximumConnections = 8
    return config
}
