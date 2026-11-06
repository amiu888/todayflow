# Obsidian sync

TodayFlow can connect to an Obsidian vault. The connection is optional: if Obsidian is not installed or not configured, TodayFlow works exactly as before.

## Set up the connection

1. Open **Settings → Obsidian**.
2. Open the **Vault** menu. TodayFlow lists the vaults registered with Obsidian, such as **NBCBrain** or **HermesBrain**; choose one. For any other folder, choose **Choose Folder…**.
3. Check the **Vault name** field. It must match the vault name Obsidian uses; it is normally the folder name.
4. Leave the sync note at `TodayFlow/Tasks.md`, or enter another vault-relative path. Use **Folder…** to put the note inside a folder such as `Conversations/Daily/TodayFlow.md`.
5. Turn on **Sync with Obsidian** and press **Save**.
6. Press **Sync now**, or wait a few seconds.

TodayFlow creates the note and its folders inside the vault. If the note already exists, anything outside TodayFlow's markers is preserved.

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

- Open **Settings → Obsidian** at any time to choose a different vault — for example switch from HermesBrain to NBCBrain — change the note folder, or edit the vault name used in links.
- One vault is synced at a time. Switching vaults stops writing the old note and starts the new one; the old note is left in place.
- Turn **Sync with Obsidian** off to stop reading and writing the vault. The existing note stays in the vault; TodayFlow does not delete it.
- If the vault path disappears, TodayFlow keeps running normally. Press **Sync now** in Settings to see the specific error.

## Troubleshooting

- **“Set up Obsidian…”** — choose a vault in Settings and enable sync.
- **The note does not open** — make sure the Obsidian app is installed and the vault name matches the name shown in Obsidian's vault switcher.
- **Changes do not sync** — confirm the note path is inside the chosen vault and the note still contains the TodayFlow markers.
- **A tag looks different** — Obsidian tags cannot contain spaces, so TodayFlow stores spaces as hyphens.
