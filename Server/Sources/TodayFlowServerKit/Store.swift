import Crypto
import Foundation
import Logging
import PostgresNIO

/// All database access.
///
/// Every row belongs to one user. The user is always taken from the device's
/// token, never from the request body, and every query filters on it — that
/// filter is the wall between users.
public struct Store: Sendable {
    let client: PostgresClient
    let logger: Logger

    public init(client: PostgresClient, logger: Logger) {
        self.client = client
        self.logger = logger
    }

    public enum StoreError: Error, CustomStringConvertible, Equatable {
        case unsupportedUpgrade(String)
        case userExists(String)
        case noSuchUser(String)
        case ambiguousDevice(String)

        public var description: String {
            switch self {
            case .unsupportedUpgrade(let why): return "Cannot upgrade the database: \(why)"
            case .userExists(let name): return "A user named '\(name)' already exists."
            case .noSuchUser(let name): return "No user named '\(name)'."
            case .ambiguousDevice(let name):
                return "More than one device is named '\(name)'. Use its id (see `devices`)."
            }
        }
    }

    // MARK: - Schema

    static let schemaVersion = 3

    /// Creates or upgrades the tables. Safe to run on every start.
    public func migrate() async throws {
        try await client.withConnection { connection in
            try await connection.query("BEGIN", logger: logger)
            do {
                // One migrator at a time, even with several server processes.
                try await connection.query("SELECT pg_advisory_xact_lock(7404)", logger: logger)
                try await connection.query(
                    "CREATE TABLE IF NOT EXISTS schema_version (version INT NOT NULL)", logger: logger
                )
                var version = 0
                for try await value in try await connection.query(
                    "SELECT max(version) FROM schema_version", logger: logger
                ).decode(Int?.self) {
                    version = value ?? 0
                }
                if version < 2 {
                    try await upgradeToMultiUser(connection)
                }
                if version < 3 {
                    // When a file stopped being used by any of its user's
                    // attachments; it is deleted after a grace period.
                    try await connection.query(
                        "ALTER TABLE blob_owner ADD COLUMN IF NOT EXISTS unreferenced_since TIMESTAMPTZ",
                        logger: logger
                    )
                }
                if version < Self.schemaVersion {
                    try await connection.query("DELETE FROM schema_version", logger: logger)
                    try await connection.query(
                        "INSERT INTO schema_version (version) VALUES (\(Self.schemaVersion))", logger: logger
                    )
                }
                try await connection.query("COMMIT", logger: logger)
            } catch {
                _ = try? await connection.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    /// Version 1 was single-user. It never held real data, so its tables are
    /// replaced — but only when they are empty; otherwise refuse to start.
    private func upgradeToMultiUser(_ connection: PostgresConnection) async throws {
        for table in ["record", "device"] {
            let exists = try await connection.query(
                "SELECT to_regclass(\(table)) IS NOT NULL", logger: logger
            )
            var present = false
            for try await value in exists.decode(Bool.self) { present = value }
            guard present else { continue }
            let rows = try await connection.query(
                "SELECT count(*) FROM \(unescaped: table)", logger: logger
            )
            for try await count in rows.decode(Int64.self) where count > 0 {
                throw StoreError.unsupportedUpgrade(
                    "the single-user table '\(table)' has \(count) rows. Back it up and empty it first."
                )
            }
        }
        let statements: [PostgresQuery] = [
            "DROP TABLE IF EXISTS record",
            "DROP TABLE IF EXISTS device",
            "CREATE SEQUENCE IF NOT EXISTS record_seq",
            """
            CREATE TABLE app_user (
              id                TEXT        PRIMARY KEY,
              name              TEXT        NOT NULL UNIQUE,
              pairing_code_hash TEXT        NOT NULL UNIQUE,
              created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
            )
            """,
            """
            CREATE TABLE device (
              id           TEXT        PRIMARY KEY,
              user_id      TEXT        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
              name         TEXT        NOT NULL,
              token_hash   TEXT        NOT NULL UNIQUE,
              created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
              last_seen_at TIMESTAMPTZ,
              revoked      BOOLEAN     NOT NULL DEFAULT FALSE
            )
            """,
            """
            CREATE TABLE record (
              user_id    TEXT        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
              entity     TEXT        NOT NULL,
              id         TEXT        NOT NULL,
              data       JSONB,
              deleted    BOOLEAN     NOT NULL DEFAULT FALSE,
              changed_at TIMESTAMPTZ NOT NULL,
              device_id  TEXT        NOT NULL,
              seq        BIGINT      NOT NULL UNIQUE,
              PRIMARY KEY (user_id, entity, id)
            )
            """,
            "CREATE INDEX record_user_seq_idx ON record (user_id, seq)",
            """
            CREATE TABLE blob_owner (
              user_id    TEXT        NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
              sha256     TEXT        NOT NULL,
              size       BIGINT      NOT NULL,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              PRIMARY KEY (user_id, sha256)
            )
            """,
            "CREATE INDEX blob_owner_sha_idx ON blob_owner (sha256)",
        ]
        for statement in statements {
            try await connection.query(statement, logger: logger)
        }
    }

    // MARK: - Secrets

    static func hash(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Cryptographically random hex (the system generator is a CSPRNG on
    /// macOS and Linux).
    static func randomHex(bytes count: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }
            .joined()
    }

    /// 96 random bits, typed once per device: `xxxxxx-xxxxxx-xxxxxx-xxxxxx` (hex).
    static func newPairingCode() -> String {
        let hex = randomHex(bytes: 12)
        return stride(from: 0, to: 24, by: 6).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return String(hex[start..<hex.index(start, offsetBy: 6)])
        }.joined(separator: "-")
    }

    /// Pairing codes are compared without dashes, spaces or case.
    static func normalizedCode(_ code: String) -> String {
        code.lowercased().filter { $0.isHexDigit }
    }

    // MARK: - Users

    /// Creates a user and returns their pairing code (shown once).
    public func addUser(name: String) async throws -> (id: String, pairingCode: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !trimmed.isEmpty else { throw StoreError.noSuchUser(name) }
        let id = UUID().uuidString
        let code = Self.newPairingCode()
        do {
            try await client.query(
                """
                INSERT INTO app_user (id, name, pairing_code_hash)
                VALUES (\(id), \(trimmed), \(Self.hash(Self.normalizedCode(code))))
                """,
                logger: logger
            )
        } catch let error as PSQLError where error.serverInfo?[.sqlState] == "23505" {
            throw StoreError.userExists(trimmed)
        }
        return (id, code)
    }

    public func users() async throws -> [UserInfo] {
        let rows = try await client.query(
            """
            SELECT u.id, u.name,
                   to_char(u.created_at AT TIME ZONE 'UTC', \(unescaped: Self.timestampSQL)),
                   (SELECT count(*) FROM device d WHERE d.user_id = u.id AND NOT d.revoked),
                   (SELECT count(*) FROM record r WHERE r.user_id = u.id AND NOT r.deleted)
            FROM app_user u ORDER BY u.created_at
            """,
            logger: logger
        )
        var result: [UserInfo] = []
        for try await (id, name, created, devices, records)
            in rows.decode((String, String, String, Int64, Int64).self)
        {
            result.append(UserInfo(id: id, name: name, createdAt: created, activeDevices: devices, records: records))
        }
        return result
    }

    /// Replaces a user's pairing code. Already-paired devices keep working.
    public func resetPairingCode(user name: String) async throws -> String {
        let code = Self.newPairingCode()
        let rows = try await client.query(
            """
            UPDATE app_user SET pairing_code_hash = \(Self.hash(Self.normalizedCode(code)))
            WHERE name = \(name) RETURNING id
            """,
            logger: logger
        )
        for try await _ in rows.decode(String.self) { return code }
        throw StoreError.noSuchUser(name)
    }

    /// Deletes a user with all their devices, rows and file ownership.
    /// Files no other user owns are removed by the server's file cleanup.
    public func deleteUser(name: String) async throws {
        let rows = try await client.query(
            "DELETE FROM app_user WHERE name = \(name) RETURNING id", logger: logger
        )
        for try await _ in rows.decode(String.self) { return }
        throw StoreError.noSuchUser(name)
    }

    // MARK: - Devices

    /// The signed-in device and the user it belongs to.
    public struct Caller: Sendable, Equatable {
        public var deviceId: String
        public var userId: String
    }

    /// Pairs a device with the user whose pairing code matches, or nil.
    public func pair(code: String, deviceName: String) async throws -> (caller: Caller, token: String)? {
        let normalized = Self.normalizedCode(code)
        guard normalized.count >= 12 else { return nil }
        let userRows = try await client.query(
            "SELECT id FROM app_user WHERE pairing_code_hash = \(Self.hash(normalized))", logger: logger
        )
        var userId: String?
        for try await id in userRows.decode(String.self) { userId = id }
        guard let userId else { return nil }

        let deviceId = UUID().uuidString
        let token = Self.randomHex(bytes: 32)
        let name = String(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        try await client.query(
            """
            INSERT INTO device (id, user_id, name, token_hash)
            VALUES (\(deviceId), \(userId), \(name.isEmpty ? "Unnamed device" : name), \(Self.hash(token)))
            """,
            logger: logger
        )
        return (Caller(deviceId: deviceId, userId: userId), token)
    }

    /// The device and user a token belongs to, or nil when unknown or revoked.
    /// The user's name, shown on the device ("Signed in as Alex").
    public func userName(id: String) async throws -> String? {
        let rows = try await client.query("SELECT name FROM app_user WHERE id = \(id)", logger: logger)
        for try await name in rows.decode(String.self) { return name }
        return nil
    }

    public func caller(forToken token: String) async throws -> Caller? {
        let rows = try await client.query(
            """
            UPDATE device SET last_seen_at = now()
            WHERE token_hash = \(Self.hash(token)) AND NOT revoked
            RETURNING id, user_id
            """,
            logger: logger
        )
        for try await (deviceId, userId) in rows.decode((String, String).self) {
            return Caller(deviceId: deviceId, userId: userId)
        }
        return nil
    }

    static let timestampSQL = #"'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'"#

    /// All devices, or one user's.
    public func devices(user: String? = nil) async throws -> [DeviceInfo] {
        let rows = try await client.query(
            """
            SELECT d.id, u.name, d.name,
                   to_char(d.created_at AT TIME ZONE 'UTC', \(unescaped: Self.timestampSQL)),
                   to_char(d.last_seen_at AT TIME ZONE 'UTC', \(unescaped: Self.timestampSQL)),
                   d.revoked
            FROM device d JOIN app_user u ON u.id = d.user_id
            WHERE \(user)::text IS NULL OR u.name = \(user)
            ORDER BY u.name, d.created_at
            """,
            logger: logger
        )
        var result: [DeviceInfo] = []
        for try await (id, userName, name, created, seen, revoked)
            in rows.decode((String, String, String, String, String?, Bool).self)
        {
            result.append(DeviceInfo(
                id: id, user: userName, name: name, createdAt: created, lastSeenAt: seen, revoked: revoked
            ))
        }
        return result
    }

    /// Revokes a device by id, or by name when exactly one active device has
    /// it. Returns how many were revoked (0 or 1).
    @discardableResult
    public func revokeDevice(idOrName: String) async throws -> Int {
        let byId = try await client.query(
            "UPDATE device SET revoked = TRUE WHERE id = \(idOrName) AND NOT revoked RETURNING id",
            logger: logger
        )
        for try await _ in byId.decode(String.self) { return 1 }
        let matches = try await client.query(
            "SELECT id FROM device WHERE name = \(idOrName) AND NOT revoked", logger: logger
        )
        var ids: [String] = []
        for try await id in matches.decode(String.self) { ids.append(id) }
        guard ids.count <= 1 else { throw StoreError.ambiguousDevice(idOrName) }
        guard let id = ids.first else { return 0 }
        try await client.query("UPDATE device SET revoked = TRUE WHERE id = \(id)", logger: logger)
        return 1
    }

    // MARK: - Push

    /// Applies each change unless the user's server copy is newer. Runs in one
    /// transaction under a lock, so sequence order equals commit order and a
    /// concurrent pull can never skip a change.
    public func push(_ changes: [Change], caller: Caller) async throws -> [PushResult] {
        try await client.withConnection { connection in
            try await connection.query("BEGIN", logger: logger)
            do {
                try await connection.query("SELECT pg_advisory_xact_lock(7403)", logger: logger)
                var results: [PushResult] = []
                for change in changes {
                    results.append(try await apply(change, caller: caller, on: connection))
                }
                try await connection.query("COMMIT", logger: logger)
                return results
            } catch {
                _ = try? await connection.query("ROLLBACK", logger: logger)
                throw error
            }
        }
    }

    private func apply(
        _ change: Change,
        caller: Caller,
        on connection: PostgresConnection
    ) async throws -> PushResult {
        let deleted = change.op == "delete"
        let json: String? = try change.data.map {
            String(decoding: try JSONEncoder().encode($0), as: UTF8.self)
        }
        // A delete keeps the last known data so it can be inspected or restored.
        let rows = try await connection.query(
            """
            INSERT INTO record (user_id, entity, id, data, deleted, changed_at, device_id, seq)
            VALUES (\(caller.userId), \(change.entity), \(change.id), \(json)::jsonb, \(deleted),
                    \(change.changedAt)::timestamptz, \(caller.deviceId), nextval('record_seq'))
            ON CONFLICT (user_id, entity, id) DO UPDATE SET
              data = COALESCE(EXCLUDED.data, record.data),
              deleted = EXCLUDED.deleted,
              changed_at = EXCLUDED.changed_at,
              device_id = EXCLUDED.device_id,
              seq = EXCLUDED.seq
            WHERE record.changed_at <= EXCLUDED.changed_at
            RETURNING seq
            """,
            logger: logger
        )
        var accepted = false
        for try await _ in rows.decode(Int64.self) { accepted = true }
        if accepted {
            return PushResult(entity: change.entity, id: change.id, status: "accepted", current: nil)
        }
        let current = try await Self.read(
            connection.query(
                """
                \(unescaped: Self.selectSQL)
                WHERE user_id = \(caller.userId) AND entity = \(change.entity) AND id = \(change.id)
                """,
                logger: logger
            )
        ).first
        return PushResult(entity: change.entity, id: change.id, status: "stale", current: current)
    }

    // MARK: - Pull

    static let selectSQL = """
        SELECT seq, entity, id, deleted,
               to_char(changed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
               data::text, device_id
        FROM record
        """

    /// The caller's user's changes after `since`, oldest first, without the
    /// caller's own. Sequence numbers are global, so a user sees gaps; only
    /// order matters.
    public func pull(since: Int64, limit: Int, caller: Caller) async throws -> PullResponse {
        // Take the push lock briefly so an in-flight push is fully visible.
        let scanned: [StoredChange] = try await client.withConnection { connection in
            try await connection.query("BEGIN", logger: logger)
            do {
                try await connection.query("SELECT pg_advisory_xact_lock(7403)", logger: logger)
                let rows = try await connection.query(
                    """
                    \(unescaped: Self.selectSQL)
                    WHERE user_id = \(caller.userId) AND seq > \(since)
                    ORDER BY seq LIMIT \(limit + 1)
                    """,
                    logger: logger
                )
                let result = try await Self.read(rows)
                try await connection.query("COMMIT", logger: logger)
                return result
            } catch {
                _ = try? await connection.query("ROLLBACK", logger: logger)
                throw error
            }
        }
        let page = Array(scanned.prefix(limit))
        return PullResponse(
            changes: page.filter { $0.deviceId != caller.deviceId },
            next: page.last?.seq ?? since,
            more: scanned.count > limit
        )
    }

    private static func read(_ rows: PostgresRowSequence) async throws -> [StoredChange] {
        var result: [StoredChange] = []
        for try await (seq, entity, id, deleted, changedAt, json, deviceId)
            in rows.decode((Int64, String, String, Bool, String, String?, String).self)
        {
            let data = try json.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
            result.append(StoredChange(
                seq: seq, entity: entity, id: id, op: deleted ? "delete" : "upsert",
                changedAt: changedAt, data: data, deviceId: deviceId
            ))
        }
        return result
    }

    // MARK: - Blob ownership

    /// Records that the caller's user has this file. Returns true when it is
    /// new *for this user* — whether another user has it is never revealed.
    public func claimBlob(sha256: String, size: Int, caller: Caller) async throws -> Bool {
        let rows = try await client.query(
            """
            INSERT INTO blob_owner (user_id, sha256, size) VALUES (\(caller.userId), \(sha256), \(Int64(size)))
            ON CONFLICT DO NOTHING RETURNING sha256
            """,
            logger: logger
        )
        for try await _ in rows.decode(String.self) { return true }
        return false
    }

    public func ownsBlob(sha256: String, caller: Caller) async throws -> Bool {
        let rows = try await client.query(
            "SELECT 1 FROM blob_owner WHERE user_id = \(caller.userId) AND sha256 = \(sha256)",
            logger: logger
        )
        for try await _ in rows.decode(Int.self) { return true }
        return false
    }

    /// Releases files no live attachment uses any more. A file is first
    /// marked; once it has stayed unused for `grace`, the user's claim is
    /// dropped (and `BlobStore.removeUnowned` deletes it when no other user
    /// has it). A file used again before then is unmarked. Returns how many
    /// claims were dropped.
    @discardableResult
    public func releaseUnusedBlobs(grace: TimeInterval = 30 * 24 * 60 * 60) async throws -> Int {
        let used = """
            EXISTS (SELECT 1 FROM record r
                    WHERE r.user_id = b.user_id AND r.entity = 'attachment' AND NOT r.deleted
                      AND r.data->>'blob_sha256' = b.sha256 AND r.data->>'deleted_at' IS NULL)
            """
        try await client.query(
            "UPDATE blob_owner b SET unreferenced_since = now() WHERE unreferenced_since IS NULL AND NOT \(unescaped: used)",
            logger: logger
        )
        try await client.query(
            "UPDATE blob_owner b SET unreferenced_since = NULL WHERE unreferenced_since IS NOT NULL AND \(unescaped: used)",
            logger: logger
        )
        let rows = try await client.query(
            """
            DELETE FROM blob_owner
            WHERE unreferenced_since < now() - make_interval(secs => \(grace)) RETURNING sha256
            """,
            logger: logger
        )
        var dropped = 0
        for try await _ in rows.decode(String.self) { dropped += 1 }
        return dropped
    }

    /// Every hash some user still owns, for the file cleanup.
    public func ownedBlobHashes() async throws -> Set<String> {
        let rows = try await client.query("SELECT DISTINCT sha256 FROM blob_owner", logger: logger)
        var result = Set<String>()
        for try await hash in rows.decode(String.self) { result.insert(hash) }
        return result
    }

    // MARK: - Status

    public func counts(caller: Caller) async throws -> (records: Int64, latestSeq: Int64) {
        let rows = try await client.query(
            "SELECT count(*), COALESCE(max(seq), 0) FROM record WHERE user_id = \(caller.userId)",
            logger: logger
        )
        for try await (count, seq) in rows.decode((Int64, Int64).self) { return (count, seq) }
        return (0, 0)
    }
}
