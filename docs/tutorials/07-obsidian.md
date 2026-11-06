# Obsidian sync

TodayFlow can connect to an Obsidian vault in two ways:

- **Local folder / iCloud** — Obsidian and the vault are on this Mac, or iCloud syncs the vault here.
- **Remote via Local REST API** — Obsidian runs on another Mac. Obsidian has **no native LAN/API server**; the **Local REST API with MCP** community plugin adds one. No folder sharing or iCloud is required.

The connection is optional: if Obsidian is not installed or not configured, TodayFlow works exactly as before.

## Set up the connection

1. Open **Settings → Obsidian**.
2. Open the **Vault** menu. TodayFlow lists the vaults registered with Obsidian, such as **NBCBrain** or **HermesBrain**; choose one. For any other folder, choose **Choose Folder…**.
3. Check the **Vault name** field. It must match the vault name Obsidian uses; it is normally the folder name.
4. Leave the sync note at `TodayFlow/Tasks.md`, or enter another vault-relative path. Use **Folder…** to put the note inside a folder such as `Conversations/Daily/TodayFlow.md`.
5. Turn on **Sync with Obsidian** and press **Save** in the bar at the bottom of Settings (or press **⌘S**). The bar stays visible while the form scrolls.
6. Press **Sync now**, or wait a few seconds.

TodayFlow creates the note and its folders inside the vault. If the note already exists, anything outside TodayFlow's markers is preserved.

## Set up a remote Obsidian via Local REST API

Obsidian itself does not listen on the network. Install the **Local REST API with MCP** plugin inside the remote Obsidian first, and open the target vault (for example **NBCBrain**) in that Obsidian window. The plugin serves the vault that is currently open.

On the remote Obsidian:

1. **Settings → Community plugins → Browse**, install **Local REST API with MCP**, and enable it.
2. Open **Settings → Local REST API with MCP**.
3. Set the binding host to **`0.0.0.0`** so it accepts LAN connections.
4. Enable the **HTTP server** (`27123`) or use HTTPS (`27124`).
5. Copy the **API key**.
6. Choose **Transport** in TodayFlow:
   - **REST** (default) uses the plugin's direct vault API.
   - **MCP** uses the plugin's MCP endpoint. Both use the same API key and reach the same vault.

On this Mac:

1. Open **TodayFlow → Settings → Obsidian**.
2. Choose **Remote**.
3. Click **Find Local REST API on LAN**. Allow the macOS **Local Network** permission when asked.
4. Select the discovered server. If it is not found, enter the host and port manually:
   - HTTP: `27123`
   - HTTPS: `27124`
5. Paste the API key, click **Test connection**, then **Save**.
6. Set the note path and press **Sync now**.

TodayFlow accepts the plugin’s self-signed HTTPS certificate for this connection. Use the feature on a trusted LAN. HTTP is unencrypted; HTTPS is encrypted but the certificate is not verified by a public authority.

**Remote opening:** with remote mode, **Open sync note** and the **Obsidian** button in a task/project call the plugin’s `/open/` endpoint, so the remote Obsidian opens the note. A local Obsidian install is not needed.

If no server appears:

- The plugin’s binding host is still `127.0.0.1` instead of `0.0.0.0`.
- The HTTP server is disabled and HTTPS is blocked by a firewall.
- macOS Local Network permission was denied for TodayFlow.
- The Macs are on different subnets or a guest Wi-Fi network isolates clients.

## What syncs

The managed block contains open tasks, today's completed tasks, and projects. Inside the block you can:

- **Check or uncheck a task** — the status changes in TodayFlow.
- **Edit a task title** — the title changes in TodayFlow.
- **Add, remove, or edit tags** — tags change in TodayFlow, including project tags on project lines.
- **Change a due date** — use the `📅 YYYY-MM-DD` and `⏰ HH:mm` tokens.
- **Add a new checklist line** — a line without a TodayFlow ID becomes a new task. Tags and a due date on the line are applied.

Safe defaults:

- Removing a line in Obsidian does **not** delete the task. Delete tasks in TodayFlow.
- New project lines are display-only; create projects in TodayFlow.
- Tasks completed before today are not included in the note.
- The note is read and written every few seconds while sync is on.

The block looks like this:

```markdown
<!-- todayflow:start -->
# TodayFlow

## Today
- [ ] Review Q4 roadmap <!-- todayflow:019... --> #launch #Q4 📅 2026-11-06 ⏰ 17:00
<!-- todayflow:end -->
```

Keep the markers if you edit around the block.

## Deep links to notes

- **Settings → Obsidian → Open sync note** opens the central note directly in Obsidian.
- In a task or project, open its detail view and click **Obsidian** in the tag row. TodayFlow creates a note under `TodayFlow/Tasks/` or `TodayFlow/Projects/` and opens it with an `obsidian://open` link.
- Per-task notes are snapshots for reference. The central sync note is the two-way note.

## Reconfigure or turn it off

- Open **Settings → Obsidian** at any time to switch between **This Mac** and **Remote**, choose a different vault — for example HermesBrain or NBCBrain — change the note folder, or edit the vault name used in local links.
- One connection is active at a time. Switching stops writing the old note and starts the new one; the old note is left in place.
- Turn **Sync with Obsidian** off to stop reading and writing the vault. The existing note stays in the vault; TodayFlow does not delete it.
- If the vault path disappears, TodayFlow keeps running normally. Press **Sync now** in Settings to see the specific error.

## Troubleshooting

- **“Set up Obsidian…”** — choose a vault in Settings and enable sync.
- **The note does not open** — make sure the Obsidian app is installed and the vault name matches the name shown in Obsidian's vault switcher.
- **Changes do not sync** — confirm the note path is inside the chosen vault and the note still contains the TodayFlow markers.
- **A tag looks different** — Obsidian tags cannot contain spaces, so TodayFlow stores spaces as hyphens.
