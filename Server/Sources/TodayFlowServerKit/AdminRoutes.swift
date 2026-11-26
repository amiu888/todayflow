import Foundation
import Hummingbird
import NIOCore

/// Settings for the admin web page.
public struct AdminConfig: Sendable {
    public var password: String
    public var sessions = AdminSessions()
    /// Wrong passwords before sign-in is refused for 10 minutes.
    public var loginLimiter = PairingLimiter(limit: 5, window: 10 * 60)
    public var wrongPasswordDelay: Duration = .seconds(1)
    /// Set when the page is served over HTTPS, so the cookie never travels in clear.
    public var secureCookie = false
    public var backups: BackupCatalog?
    /// The dumps folder as the NAS shell sees it, for the restore command.
    public var hostBackupDirectory: String?
    /// The sync address devices should use (TODAYFLOW_PUBLIC_URL), shown on
    /// the overview and next to every pairing code.
    public var publicURL: String?
    public var blobs: BlobStore?
    public var startedAt = Date()
    public var now: @Sendable () -> Date = { Date() }

    public init(password: String, backups: BackupCatalog? = nil, blobs: BlobStore? = nil) {
        self.password = password
        self.backups = backups
        self.blobs = blobs
    }
}

/// The admin web page: users, pairing codes, devices, backups, status.
///
/// Served on its own port so it can stay on the home network while the sync
/// port is shared through Tailscale. Every page needs the admin password;
/// every change is a POST carrying the session's form token (and the cookie
/// is SameSite=Strict), so another web site cannot trigger changes.
public func buildAdminRouter(store: Store, config: AdminConfig) -> Router<BasicRequestContext> {
    let router = Router()
    let sessionCookie = "tf_admin"

    // MARK: Helpers

    @Sendable func page(_ title: String, csrf: String?, active: String, _ body: String, status: HTTPResponse.Status = .ok) -> Response {
        let nav: String
        if let csrf {
            let links = [("Overview", "/"), ("Users", "/users"), ("Devices", "/devices"), ("Backups", "/backups")]
                .map { label, href in
                    "<a href=\"\(href)\"\(label == active ? " aria-current=\"page\"" : "")>\(label)</a>"
                }
                .joined()
            nav = """
                <nav>\(links)
                <form method="post" action="/logout" class="signout">
                <input type="hidden" name="csrf" value="\(csrf)"><button class="link">Sign out</button></form></nav>
                """
        } else {
            nav = ""
        }
        let html = """
            <!doctype html><html lang="en"><head><meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(AdminSecurity.html(title)) · TodayFlow Server</title>
            <link rel="stylesheet" href="/admin.css"></head>
            <body><header><div class="brand">TodayFlow <span>Server</span></div>\(nav)</header>
            <main>\(body)</main></body></html>
            """
        return Response(
            status: status,
            headers: [
                .contentType: "text/html; charset=utf-8",
                .cacheControl: "no-store",
                .contentSecurityPolicy: "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
                .xContentTypeOptions: "nosniff",
                .init("Referrer-Policy")!: "no-referrer",
            ],
            body: ResponseBody(byteBuffer: ByteBuffer(string: html))
        )
    }

    @Sendable func redirect(_ location: String, cookie: Cookie? = nil) -> Response {
        var response = Response(status: .seeOther, headers: [.location: location, .cacheControl: "no-store"])
        if let cookie { response.setCookie(cookie) }
        return response
    }

    /// The live session's form token, or nil when signed out.
    @Sendable func session(_ request: Request) async -> (id: String, csrf: String)? {
        guard let id = request.cookies[sessionCookie]?.value,
              let csrf = await config.sessions.csrf(for: id, now: config.now())
        else { return nil }
        return (id, csrf)
    }

    @Sendable func form(_ request: Request) async throws -> [String: String] {
        let buffer = try await request.body.collect(upTo: 64 * 1024)
        var fields: [String: String] = [:]
        for pair in String(buffer: buffer).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
            }
            if let key = parts.first { fields[key] = parts.count > 1 ? parts[1] : "" }
        }
        return fields
    }

    /// Signed in and the form carries this session's token, or nil.
    @Sendable func authorizedForm(_ request: Request) async throws -> (csrf: String, fields: [String: String])? {
        guard let current = await session(request) else { return nil }
        let fields = try await form(request)
        guard let sent = fields["csrf"], AdminSecurity.equal(sent, current.csrf) else { return nil }
        return (current.csrf, fields)
    }

    @Sendable func hidden(_ csrf: String) -> String {
        "<input type=\"hidden\" name=\"csrf\" value=\"\(csrf)\">"
    }

    @Sendable func notice(_ request: Request) -> String {
        let messages = [
            "added": "User added.", "deleted": "User deleted.", "revoked": "Device signed out.",
            "backup": "Backup requested. It appears below within about 30 seconds.",
        ]
        guard let key = request.uri.queryParameters["done"].map(String.init), let text = messages[key] else { return "" }
        return "<p class=\"notice\">\(text)</p>"
    }

    @Sendable func h(_ text: String) -> String { AdminSecurity.html(text) }

    @Sendable func friendly(_ timestamp: String?) -> String {
        guard let timestamp, let date = parseTimestamp(timestamp) else { return "never" }
        return friendlyDate(date)
    }

    @Sendable func friendlyDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy, HH:mm 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    @Sendable func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    // MARK: Static

    router.get("admin.css") { _, _ in
        Response(
            status: .ok,
            headers: [.contentType: "text/css; charset=utf-8", .cacheControl: "max-age=3600"],
            body: ResponseBody(byteBuffer: ByteBuffer(string: adminCSS))
        )
    }

    // MARK: Sign in / out

    router.get("login") { request, _ -> Response in
        if await session(request) != nil { return redirect("/") }
        return page("Sign in", csrf: nil, active: "", loginForm(error: nil))
    }

    router.post("login") { request, _ -> Response in
        let limiter = config.loginLimiter
        guard await !limiter.isLocked(now: config.now()) else {
            return page("Sign in", csrf: nil, active: "",
                        loginForm(error: "Too many wrong passwords. Try again in 10 minutes."), status: .tooManyRequests)
        }
        let fields = try await form(request)
        guard let password = fields["password"], AdminSecurity.equal(password, config.password) else {
            await limiter.recordFailure(now: config.now())
            try await Task.sleep(for: config.wrongPasswordDelay)
            return page("Sign in", csrf: nil, active: "", loginForm(error: "Wrong password."), status: .unauthorized)
        }
        let created = await config.sessions.create(now: config.now())
        let cookie = Cookie(
            name: sessionCookie, value: created.id, maxAge: Int(config.sessions.lifetime), path: "/",
            secure: config.secureCookie, httpOnly: true, sameSite: .strict
        )
        return redirect("/", cookie: cookie)
    }

    router.post("logout") { request, _ -> Response in
        if let current = await session(request) {
            let fields = try await form(request)
            if let sent = fields["csrf"], AdminSecurity.equal(sent, current.csrf) {
                await config.sessions.end(current.id)
            }
        }
        let cleared = Cookie(name: sessionCookie, value: "", maxAge: 0, path: "/",
                             secure: config.secureCookie, httpOnly: true, sameSite: .strict)
        return redirect("/login", cookie: cleared)
    }

    // MARK: Overview

    router.get("/") { request, _ -> Response in
        guard let current = await session(request) else { return redirect("/login") }
        let users = try await store.users()
        let devices = try await store.devices()
        let active = devices.filter { !$0.revoked }
        let rows = users.reduce(Int64(0)) { $0 + $1.records }
        let files = config.blobs.map { ($0.allHashes().count, $0.totalSize()) }
        let latest = config.backups?.dumps().first
        let uptime = Int(config.now().timeIntervalSince(config.startedAt))
        let tiles = [
            ("Users", "\(users.count)"),
            ("Active devices", "\(active.count)"),
            ("Synced rows", "\(rows)"),
            ("Files", files.map { $0.0 == 0 ? "none yet" : "\($0.0) · \(bytes($0.1))" } ?? "off"),
            ("Last backup", latest.map { friendlyDate($0.created) } ?? "none yet"),
            ("Running for", uptime < 3600 ? "\(uptime / 60) min" : uptime < 86_400 ? "\(uptime / 3600) h" : "\(uptime / 86_400) days"),
        ]
        .map { "<div class=\"tile\"><div class=\"label\">\($0.0)</div><div class=\"value\">\(h($0.1))</div></div>" }
        .joined()
        let recent = active.sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }.prefix(5).map {
            "<tr><td>\(h($0.name))</td><td>\(h($0.user))</td><td>\(friendly($0.lastSeenAt))</td></tr>"
        }.joined()
        var body = "<h1>Overview</h1>"
        if let url = config.publicURL {
            body += "<p class=\"hint\">Sync address for TodayFlow ▸ Settings ▸ Sync: <strong class=\"address\">\(h(url))</strong></p>"
        }
        body += "<div class=\"tiles\">\(tiles)</div>"
        if users.isEmpty {
            body += "<p class=\"empty\">No users yet. <a href=\"/users\">Add the first user</a> to get a pairing code.</p>"
        }
        if !recent.isEmpty {
            body += "<h2>Recently active devices</h2><div class=\"scroll\"><table><thead><tr><th>Device</th><th>User</th><th>Last seen</th></tr></thead><tbody>\(recent)</tbody></table></div>"
        }
        return page("Overview", csrf: current.csrf, active: "Overview", body)
    }

    // MARK: Users

    router.get("users") { request, _ -> Response in
        guard let current = await session(request) else { return redirect("/login") }
        let users = try await store.users()
        let rows = users.map { user in
            """
            <tr><td><strong>\(h(user.name))</strong></td><td>\(user.activeDevices)</td><td>\(user.records)</td>
            <td>\(friendly(user.createdAt))</td>
            <td class="actions">
            <form method="post" action="/users/code">\(hidden(current.csrf))<input type="hidden" name="name" value="\(h(user.name))">
            <button>New pairing code</button></form>
            <a class="danger" href="/users/delete?name=\(h(user.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""))">Delete…</a>
            </td></tr>
            """
        }.joined()
        let table = users.isEmpty
            ? "<p class=\"empty\">No users yet.</p>"
            : "<div class=\"scroll\"><table><thead><tr><th>User</th><th>Devices</th><th>Rows</th><th>Created</th><th></th></tr></thead><tbody>\(rows)</tbody></table></div>"
        let body = """
            <h1>Users</h1>\(notice(request))
            <p class="hint">Each user has their own tasks. A device pairs as one user and never sees another user's data.</p>
            \(table)
            <h2>Add a user</h2>
            <form method="post" action="/users/add" class="inline">\(hidden(current.csrf))
            <label>Name <input name="name" required maxlength="100" autocomplete="off" placeholder="e.g. Alex or Test"></label>
            <button class="primary">Add user</button></form>
            """
        return page("Users", csrf: current.csrf, active: "Users", body)
    }

    @Sendable func codePage(csrf: String, user: String, code: String, isNew: Bool) -> Response {
        let body = """
            <h1>\(isNew ? "User added" : "New pairing code")</h1>
            <p>Pairing code for <strong>\(h(user))</strong>:</p>
            <p class="code">\(h(code))</p>
            \(config.publicURL.map { "<p>Server address: <strong class=\"address\">\(h($0))</strong></p>" } ?? "")
            <p class="hint">Type it once in TodayFlow ▸ Settings ▸ Sync on each of \(h(user))'s devices.
            It is shown only now. \(isNew ? "" : "The old code no longer works; devices already paired keep working.")</p>
            <p><a href="/users">Back to users</a></p>
            """
        return page("Pairing code", csrf: csrf, active: "Users", body)
    }

    router.post("users/add") { request, _ -> Response in
        guard let (csrf, fields) = try await authorizedForm(request) else { return redirect("/login") }
        let name = (fields["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return redirect("/users") }
        do {
            let user = try await store.addUser(name: name)
            return codePage(csrf: csrf, user: name, code: user.pairingCode, isNew: true)
        } catch let error as Store.StoreError {
            return page("Users", csrf: csrf, active: "Users",
                        "<h1>Users</h1><p class=\"error\">\(h(error.description))</p><p><a href=\"/users\">Back</a></p>",
                        status: .conflict)
        }
    }

    router.post("users/code") { request, _ -> Response in
        guard let (csrf, fields) = try await authorizedForm(request) else { return redirect("/login") }
        let name = fields["name"] ?? ""
        let code = try await store.resetPairingCode(user: name)
        return codePage(csrf: csrf, user: name, code: code, isNew: false)
    }

    router.get("users/delete") { request, _ -> Response in
        guard let current = await session(request) else { return redirect("/login") }
        let name = request.uri.queryParameters["name"].map(String.init) ?? ""
        guard let user = try await store.users().first(where: { $0.name == name }) else { return redirect("/users") }
        let body = """
            <h1>Delete \(h(user.name))?</h1>
            <p class="error">This deletes the user, signs out their \(user.activeDevices) device(s), and removes
            their \(user.records) synced row(s) and files from the server. It cannot be undone here
            (backups and snapshots still have them).</p>
            <p class="hint">Their devices keep their own local copy of their tasks.</p>
            <form method="post" action="/users/delete">\(hidden(current.csrf))
            <input type="hidden" name="name" value="\(h(user.name))">
            <label>Type <strong>\(h(user.name))</strong> to confirm
            <input name="confirm" required autocomplete="off"></label>
            <div class="row"><button class="danger">Delete user</button><a href="/users">Cancel</a></div></form>
            """
        return page("Delete user", csrf: current.csrf, active: "Users", body)
    }

    router.post("users/delete") { request, _ -> Response in
        guard let (_, fields) = try await authorizedForm(request) else { return redirect("/login") }
        let name = fields["name"] ?? ""
        guard !name.isEmpty, fields["confirm"] == name else {
            return redirect("/users/delete?name=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")")
        }
        try await store.deleteUser(name: name)
        return redirect("/users?done=deleted")
    }

    // MARK: Devices

    router.get("devices") { request, _ -> Response in
        guard let current = await session(request) else { return redirect("/login") }
        let devices = try await store.devices()
        let rows = devices.map { device in
            let action = device.revoked
                ? "<span class=\"muted\">signed out</span>"
                : """
                  <form method="post" action="/devices/revoke">\(hidden(current.csrf))
                  <input type="hidden" name="id" value="\(h(device.id))"><button>Sign out device</button></form>
                  """
            return """
                <tr\(device.revoked ? " class=\"revoked\"" : "")><td><strong>\(h(device.name))</strong></td>
                <td>\(h(device.user))</td><td>\(friendly(device.createdAt))</td><td>\(friendly(device.lastSeenAt))</td>
                <td class="actions">\(action)</td></tr>
                """
        }.joined()
        let table = devices.isEmpty
            ? "<p class=\"empty\">No devices have paired yet.</p>"
            : "<div class=\"scroll\"><table><thead><tr><th>Device</th><th>User</th><th>Paired</th><th>Last seen</th><th></th></tr></thead><tbody>\(rows)</tbody></table></div>"
        let body = """
            <h1>Devices</h1>\(notice(request))
            <p class="hint">Signing a device out stops it syncing at once. It keeps its local tasks and can pair again with the user's code.</p>
            \(table)
            """
        return page("Devices", csrf: current.csrf, active: "Devices", body)
    }

    router.post("devices/revoke") { request, _ -> Response in
        guard let (_, fields) = try await authorizedForm(request) else { return redirect("/login") }
        if let id = fields["id"], !id.isEmpty { try await store.revokeDevice(idOrName: id) }
        return redirect("/devices?done=revoked")
    }

    // MARK: Backups

    router.get("backups") { request, _ -> Response in
        guard let current = await session(request) else { return redirect("/login") }
        guard let catalog = config.backups else {
            return page("Backups", csrf: current.csrf, active: "Backups",
                        "<h1>Backups</h1><p class=\"empty\">The backup folder is not connected to this server.</p>")
        }
        let dumps = catalog.dumps()
        let rows = dumps.map {
            "<tr><td>\(friendlyDate($0.created))</td><td>\(bytes($0.size))</td><td class=\"actions\"><a href=\"/backups/\($0.name)\">Download</a></td></tr>"
        }.joined()
        let pending = catalog.isBackupPending
            ? "<p class=\"notice\">A backup is being made. Reload in a moment.</p>" : ""
        let table = dumps.isEmpty
            ? "<p class=\"empty\">No backups yet.</p>"
            : "<div class=\"scroll\"><table><thead><tr><th>Made</th><th>Size</th><th></th></tr></thead><tbody>\(rows)</tbody></table></div>"
        let body = """
            <h1>Backups</h1>\(notice(request))\(pending)
            <p class="hint">The database is dumped every day and the newest 14 are kept. Attachment files are
            covered by the NAS's hourly snapshots of the TodayFlow dataset.</p>
            <form method="post" action="/backups/now" class="spaced">\(hidden(current.csrf))<button class="primary">Back up now</button></form>
            \(table)
            <h2>Restoring</h2>
            <p class="hint">Restoring replaces everything on the server, for every user, so it is done from the NAS
            shell rather than this page. In the NAS shell (as an admin), run:</p>
            <pre>sudo docker exec -i $(sudo docker ps -qf name=todayflow-db) pg_restore -U todayflow -d todayflow --clean \\
            &lt; \(AdminSecurity.html(config.hostBackupDirectory ?? "<backup folder>"))/&lt;file&gt;.dump</pre>
            <p class="hint">Then restart the TodayFlow app in TrueNAS ▸ Apps. Devices pick up the restored state on their next sync.</p>
            """
        return page("Backups", csrf: current.csrf, active: "Backups", body)
    }

    router.post("backups/now") { request, _ -> Response in
        guard try await authorizedForm(request) != nil else { return redirect("/login") }
        try config.backups?.requestBackup()
        return redirect("/backups?done=backup")
    }

    router.get("backups/:name") { request, context -> Response in
        guard await session(request) != nil else { return redirect("/login") }
        guard let name = context.parameters.get("name"),
              let url = config.backups?.url(of: name),
              let data = try? Data(contentsOf: url)
        else { throw HTTPError(.notFound) }
        return Response(
            status: .ok,
            headers: [
                .contentType: "application/octet-stream",
                .contentDisposition: "attachment; filename=\"\(name)\"",
                .cacheControl: "no-store",
            ],
            body: ResponseBody(byteBuffer: ByteBuffer(data: data))
        )
    }

    return router
}

private func loginForm(error: String?) -> String {
    """
    <div class="login"><h1>Sign in</h1>
    \(error.map { "<p class=\"error\">\(AdminSecurity.html($0))</p>" } ?? "")
    <form method="post" action="/login">
    <label>Admin password <input type="password" name="password" required autofocus autocomplete="current-password"></label>
    <button class="primary">Sign in</button></form></div>
    """
}

extension BlobStore {
    /// Bytes used by all stored files.
    public func totalSize() -> Int64 {
        allHashes().reduce(Int64(0)) { total, hash in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(for: hash).path)[.size] as? NSNumber)??
                .int64Value ?? 0
            return total + size
        }
    }
}

let adminCSS = """
:root {
  --bg: #f6f6f4; --surface: #ffffff; --text: #1c1c1e; --muted: #6e6e73; --line: #e3e3e0;
  --accent: #2f6fde; --accent-text: #ffffff; --danger: #c2362b; --notice: #e8f1ff; --code: #f0efe9;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #161617; --surface: #1f1f21; --text: #f2f2f2; --muted: #9a9aa0; --line: #333336;
    --accent: #5a8ff0; --accent-text: #0d0d0e; --danger: #ff6b5e; --notice: #1d2a40; --code: #2a2a2d;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; }
header { display: flex; align-items: center; gap: 24px; padding: 14px 24px;
  background: var(--surface); border-bottom: 1px solid var(--line); flex-wrap: wrap; }
.brand { font-weight: 700; letter-spacing: -0.01em; }
.brand span { color: var(--muted); font-weight: 500; }
nav { display: flex; align-items: center; gap: 4px; flex: 1; min-width: 0; overflow-x: auto; }
nav a { white-space: nowrap; }
nav a { color: var(--text); text-decoration: none; padding: 6px 10px; border-radius: 6px; }
nav a:hover { background: var(--bg); }
nav a[aria-current="page"] { background: var(--bg); font-weight: 600; }
nav .signout { margin-left: auto; }
main { max-width: 960px; margin: 0 auto; padding: 24px 16px 64px; }
.scroll { overflow-x: auto; border-radius: 10px; }
form.spaced { margin: 4px 0 16px; }
h1 { font-size: 24px; margin: 8px 0 16px; letter-spacing: -0.01em; }
h2 { font-size: 17px; margin: 32px 0 10px; }
.tiles { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 12px; }
.tile { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; }
.tile .label { color: var(--muted); font-size: 13px; }
.tile .value { font-size: 20px; font-weight: 600; margin-top: 2px; }
table { width: 100%; border-collapse: collapse; background: var(--surface);
  border: 1px solid var(--line); border-radius: 10px; overflow: hidden; }
th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--line); vertical-align: middle; }
th { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: var(--muted); font-weight: 600; }
tr:last-child td { border-bottom: 0; }
tr.revoked td { color: var(--muted); }
td.actions { text-align: right; white-space: nowrap; }
td.actions form { display: inline; }
td.actions > * + * { margin-left: 10px; }
button { font: inherit; padding: 6px 12px; border-radius: 6px; border: 1px solid var(--line);
  background: var(--surface); color: var(--text); cursor: pointer; }
button:hover { border-color: var(--muted); }
button.primary { background: var(--accent); color: var(--accent-text); border-color: var(--accent); font-weight: 600; }
button.danger { background: var(--danger); color: #fff; border-color: var(--danger); font-weight: 600; }
button.link { border: 0; background: none; color: var(--muted); padding: 6px 10px; }
a { color: var(--accent); }
a.danger { color: var(--danger); }
label { display: flex; flex-direction: column; gap: 6px; font-weight: 500; max-width: 360px; margin-bottom: 12px; }
input { font: inherit; padding: 8px 10px; border: 1px solid var(--line); border-radius: 6px;
  background: var(--surface); color: var(--text); }
input:focus, button:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
form.inline { display: flex; align-items: flex-end; gap: 10px; flex-wrap: wrap; }
form.inline label { margin-bottom: 0; flex: 1; min-width: 220px; }
.row { display: flex; gap: 14px; align-items: center; }
.hint { color: var(--muted); max-width: 680px; }
.empty { color: var(--muted); padding: 18px; background: var(--surface); border: 1px dashed var(--line); border-radius: 10px; }
.notice { background: var(--notice); padding: 10px 14px; border-radius: 8px; }
.error { color: var(--danger); }
.muted { color: var(--muted); }
.code { font: 600 26px/1.2 ui-monospace, SFMono-Regular, Menlo, monospace; letter-spacing: 0.04em;
  background: var(--code); padding: 16px 20px; border-radius: 10px; display: inline-block; user-select: all; }
pre { background: var(--code); padding: 12px 14px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
.login { max-width: 360px; margin: 64px auto; background: var(--surface); border: 1px solid var(--line);
  border-radius: 12px; padding: 24px; }
.login label { max-width: none; }
@media (max-width: 640px) {
  th:nth-child(3), td:nth-child(3), th:nth-child(4), td:nth-child(4) { display: none; }
  header { flex-direction: column; align-items: stretch; gap: 8px; padding: 12px 16px; }
  td.actions { white-space: normal; }
  td.actions > * { display: block; margin: 4px 0 0 auto; width: max-content; }
  td.actions > * + * { margin-left: auto; }
  th, td { padding: 10px; }
}
"""
