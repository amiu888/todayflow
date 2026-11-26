import Foundation
import Hummingbird
import Logging
import PostgresNIO
import ServiceLifecycle
import TodayFlowServerKit

let usage = """
    Usage:
      TodayFlowServer                          run the server
      TodayFlowServer adduser <name>           create a user; prints their pairing code
      TodayFlowServer users                    list users
      TodayFlowServer resetcode <name>         new pairing code (paired devices keep working)
      TodayFlowServer deluser <name> --yes     delete a user and ALL their data
      TodayFlowServer devices [user]           list devices
      TodayFlowServer revoke <device id|name>  sign a device out
    """

let env = ProcessInfo.processInfo.environment
let arguments = Array(CommandLine.arguments.dropFirst())
let logger: Logger = {
    var logger = Logger(label: "todayflow-server")
    logger.logLevel = env["LOG_LEVEL"].flatMap { Logger.Level(rawValue: $0) } ?? .info
    return logger
}()
// Admin commands start the pool and query at once; keep its startup chatter quiet.
let poolLogger: Logger = {
    var poolLogger = logger
    if !arguments.isEmpty { poolLogger.logLevel = .error }
    return poolLogger
}()

let client = PostgresClient(configuration: postgresConfiguration(env), backgroundLogger: poolLogger)
let store = Store(client: client, logger: poolLogger)

/// Runs one admin command with the connection pool alive, then exits.
func runAdmin(_ body: @escaping @Sendable () async throws -> Void) async -> Never {
    let pool = Task { await client.run() }
    var code: Int32 = 0
    do {
        try await store.migrate()
        try await body()
    } catch let error as Store.StoreError {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        code = 1
    } catch {
        FileHandle.standardError.write(Data("error: \(String(reflecting: error))\n".utf8))
        code = 1
    }
    pool.cancel()
    exit(code)
}

func requireArguments(_ count: Int) {
    guard arguments.count == count else {
        print(usage)
        exit(2)
    }
}

switch arguments.first {
case nil:
    break
case "adduser":
    requireArguments(2)
    await runAdmin {
        let user = try await store.addUser(name: arguments[1])
        print("Created user '\(arguments[1])'.")
        print("Pairing code: \(user.pairingCode)")
        print("Type it once on each of this user's devices. It is not shown again (use resetcode for a new one).")
    }
case "users":
    requireArguments(1)
    await runAdmin {
        let users = try await store.users()
        if users.isEmpty { print("No users. Create one with: TodayFlowServer adduser <name>") }
        for user in users {
            print("\(user.name)  \(user.activeDevices) device(s)  \(user.records) row(s)  created \(user.createdAt)")
        }
    }
case "resetcode":
    requireArguments(2)
    await runAdmin {
        let code = try await store.resetPairingCode(user: arguments[1])
        print("New pairing code for '\(arguments[1])': \(code)")
        print("The old code no longer works. Paired devices keep working.")
    }
case "deluser":
    guard arguments.count == 3, arguments[2] == "--yes" else {
        print("This deletes the user, their devices and ALL their synced data on the server.")
        print("Devices keep their own local copy. To confirm: TodayFlowServer deluser <name> --yes")
        exit(2)
    }
    await runAdmin {
        try await store.deleteUser(name: arguments[1])
        print("Deleted user '\(arguments[1])'. Their files are removed at the next cleanup.")
    }
case "devices":
    guard arguments.count <= 2 else {
        print(usage)
        exit(2)
    }
    await runAdmin {
        let devices = try await store.devices(user: arguments.count == 2 ? arguments[1] : nil)
        if devices.isEmpty { print("No paired devices.") }
        for device in devices {
            let state = device.revoked ? "revoked" : "active "
            print("\(device.id)  \(state)  user \(device.user)  paired \(device.createdAt)  last seen \(device.lastSeenAt ?? "never")  \(device.name)")
        }
    }
case "revoke":
    requireArguments(2)
    await runAdmin {
        let count = try await store.revokeDevice(idOrName: arguments[1])
        print(count == 0 ? "No active device matched." : "Revoked. That device must pair again to sync.")
    }
default:
    print(usage)
    exit(2)
}

// MARK: - Server

let blobRoot = URL(fileURLWithPath: env["TODAYFLOW_BLOB_DIR"] ?? "./data/blobs", isDirectory: true)
try FileManager.default.createDirectory(at: blobRoot, withIntermediateDirectories: true)
let blobs = BlobStore(root: blobRoot)

/// Daily: deletes files no user owns any more (after deluser).
struct BlobCleanup: Service {
    func run() async throws {
        while !Task.isCancelled {
            do {
                let released = try await store.releaseUnusedBlobs()
                let removed = blobs.removeUnowned(keeping: try await store.ownedBlobHashes())
                if released + removed > 0 {
                    logger.info("File cleanup: \(released) unused for 30 days released, \(removed) file(s) deleted.")
                }
            } catch {
                logger.warning("File cleanup failed: \(error)")
            }
            try await Task.sleep(for: .seconds(24 * 60 * 60))
        }
    }
}

var serverConfig = ServerConfig(blobs: blobs)
// Lets paired devices reach their Obsidian Local REST API through this
// server. TODAYFLOW_OBSIDIAN_PROXY=off turns it off.
if env["TODAYFLOW_OBSIDIAN_PROXY"]?.lowercased() != "off" {
    serverConfig.obsidian = ObsidianProxy(client: ObsidianProxy.makeHTTPClient())
}

let app = Application(
    router: buildRouter(store: store, config: serverConfig),
    configuration: .init(
        address: .hostname(env["HOST"] ?? "0.0.0.0", port: env["PORT"].flatMap { Int($0) } ?? 8787),
        serverName: "TodayFlowServer"
    ),
    services: [client],
    onServerRunning: { _ in logger.info("TodayFlow Sync Server is running.") },
    logger: logger
)
var running = app
running.beforeServerStarts {
    try await store.migrate()
    let users = try await store.users()
    logger.info("Database ready: \(users.count) user(s). Files in \(blobRoot.path).")
    if users.isEmpty {
        logger.warning("No users yet. Create one with: TodayFlowServer adduser <name>")
    }
}
running.addServices(BlobCleanup())

// The admin page runs only when it has a password, on its own port.
if let password = env["TODAYFLOW_ADMIN_PASSWORD"] {
    guard password.count >= 12 else {
        logger.critical("TODAYFLOW_ADMIN_PASSWORD must be at least 12 characters.")
        exit(1)
    }
    let backups = env["TODAYFLOW_BACKUP_DIR"].map { dir in
        BackupCatalog(
            backups: URL(fileURLWithPath: dir, isDirectory: true),
            control: URL(fileURLWithPath: env["TODAYFLOW_CONTROL_DIR"] ?? "\(dir)/control", isDirectory: true)
        )
    }
    var adminConfig = AdminConfig(password: password, backups: backups, blobs: blobs)
    adminConfig.secureCookie = env["TODAYFLOW_ADMIN_SECURE_COOKIE"] == "1"
    adminConfig.hostBackupDirectory = env["TODAYFLOW_HOST_BACKUP_DIR"]
    adminConfig.publicURL = env["TODAYFLOW_PUBLIC_URL"].flatMap { $0.isEmpty ? nil : $0 }
    let adminPort = env["ADMIN_PORT"].flatMap { Int($0) } ?? 8788
    let admin = Application(
        router: buildAdminRouter(store: store, config: adminConfig),
        configuration: .init(address: .hostname(env["HOST"] ?? "0.0.0.0", port: adminPort), serverName: "TodayFlowAdmin"),
        onServerRunning: { _ in logger.info("Admin page on port \(adminPort).") },
        logger: logger
    )
    running.addServices(admin)
} else {
    logger.info("Admin page off (set TODAYFLOW_ADMIN_PASSWORD to turn it on).")
}
try await running.runService()
