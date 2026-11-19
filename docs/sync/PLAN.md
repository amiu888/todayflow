# TodayFlow Sync — Detailed Plan

Status: **design approved in outline; build not authorized yet.** A server
prototype exists (see `HANDOFF.md`). Last updated 2026-11-19.

## 1. Goal

Run TodayFlow on several devices, on the LAN or over the internet, with one
central database, while every device keeps working from its own local database
when the server is unreachable.

Non-goals for this version: several users or shared workspaces, several central
databases, real-time collaboration, a web or iPhone client (the protocol must
not prevent them later).

## 2. Architecture

```
 Mac A (SQLite) ─┐
 Mac B (SQLite) ─┼── HTTPS ──▶ TodayFlow Sync Server ──▶ Postgres
 later: web/phone┘             (Docker Compose on TrueNAS)   + blob files
```

- **Local-first.** The app reads and writes SQLite exactly as today. Sync is a
  background job that pushes local changes and pulls remote ones.
- **One server**, single user, hosted on TrueNAS SCALE 25.04 (runs Docker
  Compose apps natively). Reached directly on the LAN and through Tailscale
  from outside; no ports opened to the internet.
- **Generic storage.** The server stores each app row as a JSON document keyed
  by (table name, row id). App schema changes need no server migration.

## 3. Server

### 3.1 Tables (Postgres)

| Table | Columns | Notes |
|---|---|---|
| `record` | `entity`, `id` (PK together), `data` JSONB, `deleted`, `changed_at`, `device_id`, `seq` | Latest state of one app row. `seq` unique, from sequence `record_seq`. |
| `device` | `id`, `name`, `token_hash` (unique), `created_at`, `last_seen_at`, `revoked` | Token stored only as SHA-256. |
| `blob` (phase 5) | `sha256` (PK), `size`, `created_at` | File bytes on disk at `blobs/<sha256>`. |

### 3.2 API

All `/v1` calls except `/pair` need `Authorization: Bearer <device token>`.

| Call | Request | Response |
|---|---|---|
| `GET /health` | — | `ok` |
| `POST /v1/pair` | `{pairingCode, deviceName}` | `{deviceId, token}`; wrong code → 401 after a 1 s delay |
| `GET /v1/status` | — | `{ok, records, latestSeq, deviceId}` |
| `POST /v1/push` | `{changes:[{entity, id, op, changedAt, data}]}`; `op` is `upsert` or `delete`; max 1000 per call | `{results:[{entity, id, status, current?}]}`; `status` is `accepted` or `stale` (then `current` is the server's newer copy) |
| `GET /v1/pull?since=N&limit=M` | — | `{changes:[{seq, entity, id, op, changedAt, data, deviceId}], next, more}`; excludes the caller's own changes; `next` always advances |
| `PUT /v1/blobs/{sha256}` (phase 5) | file bytes | 201, or 200 if already stored; server verifies the hash |
| `GET /v1/blobs/{sha256}` (phase 5) | — | file bytes |

### 3.3 Rules

- **Conflict:** a change is accepted when its `changedAt` is equal to or later
  than the stored one (whole row, last writer wins). Otherwise it is `stale`.
- **Ordering:** push and pull run under one Postgres advisory lock, so `seq`
  order equals commit order and a pull can never skip an in-flight push.
- **Deletes** are soft: `deleted = true`, last `data` kept.
- **Clock guard (to add):** reject `changedAt` more than 10 minutes in the
  future, so a device with a wrong clock cannot win every conflict.

## 4. App changes

### 4.1 Change capture — SQLite triggers (new migration v9)

Finding: the existing `change_outbox` is written only for `work_item`,
`attachment`, and `item_link`. Contacts, groups, reminders, action items,
activity, and hard deletes never reach it. Completing it by hand in every
repository is error-prone, so capture moves to triggers.

- New table `sync_change(entity, entity_id, op, changed_at)` with primary key
  (`entity`, `entity_id`): one pending row per changed app row, coalesced.
- `AFTER INSERT/UPDATE/DELETE` triggers on every synced table write into it,
  guarded by `WHEN (SELECT value FROM sync_flag WHERE key='applying') = 0`.
- The sync engine reads the **current row** at push time and sends all its
  columns as JSON, so the payload is always complete and current.
- `change_outbox` stays untouched for now (no reader); remove it in a later
  cleanup once sync is proven.

Synced tables and row ids:

| Table | Row id sent to server | Notes |
|---|---|---|
| `work_item` | `id` | tasks, subtasks, projects |
| `action_item`, `attachment`, `item_link`, `reminder`, `contact`, `contact_group` | `id` | |
| `contact_group_member` | `contact_id|group_id` | no timestamps; hard deletes |
| `task_contact` | `task_id|contact_id` | hard deletes |
| `activity` | `id` | append-only, never conflicts |
| `setting` | `key` | **only** allow-listed keys: `work_trays`, `workflow_rules`, `today_sort` |

Never synced: `ai_endpoint` (may hold an API key), `ai_setup_complete`,
`due_nudge_memory`, window layout, `search_index`, `change_outbox`,
`sync_change`, GRDB bookkeeping.

Known limitation: trays live in one JSON value (`setting.work_trays`), so two
devices editing trays offline at the same time lose one side. Fix later by
moving trays to their own table.

### 4.2 Device identity

Every install writes `device_id = "local"`. Generate a UUID once, keep it in
`UserDefaults`, and pass it wherever `"local"` is hard-coded
(`WindowManager.swift`, `CaptureWindowController.swift`, four `*Record.swift`
files). The server-issued `deviceId` from pairing is separate and used only by
the server.

### 4.3 Sync engine (`TodayFlowSync`)

Replaces `NoopSyncEngine` behind the existing `SyncEngine` protocol
(`pushPending()`, `pull()`).

1. **Push:** read `sync_change` in batches of 500, build changes from current
   rows, `POST /v1/push`. For `accepted`, delete the `sync_change` row if it
   has not changed again since it was read. For `stale`, apply `current`
   locally and delete the `sync_change` row.
2. **Pull:** `GET /v1/pull?since=<cursor>` until `more` is false. Apply each
   page in **one transaction**: set `sync_flag.applying = 1`, upsert or delete
   rows, set the flag back, store the new cursor. Cursor lives in `sync_state`.
3. **Apply rules:** write only columns the local table has; skip an incoming
   row when a local unpushed change to it is newer; apply parents before
   children within a page (work items before attachments) or defer foreign
   keys to commit.
4. **Search index:** existing FTS triggers on `work_item` and `attachment`
   keep `search_index` current during apply; verify they still fire with the
   sync flag set.
5. **Schedule:** on launch, 3 s after a local change (debounced), every 30 s
   while running, on wake from sleep, and on "Sync now".
6. **Failure:** network errors back off (5 s → 5 min) and never block the UI;
   a 401 turns sync off and shows "This device was signed out".

### 4.4 Settings ▸ Sync

Server address (must be `https://`, or `http://` only for a private LAN
address), pairing code field, Pair button, on/off switch, last-synced time,
pending-change count, "Sync now", last error, "Unpair this device". Token in
the Keychain.

### 4.5 First sync

1. Take a database backup (existing `DatabaseBackup`).
2. Mark every existing row as pending (fill `sync_change` from all synced
   tables, `changed_at` = the row's `updated_at` or `created_at`).
3. Pull everything, then push. Rows combine by id; duplicates of the same
   contact entered on two Macs are handled by the existing duplicate merge.

### 4.6 Attachments (phase 5)

- Files copied into the app container (`local_copy_path` set) upload as blobs
  and download on demand on other devices.
- Linked files keep a security-scoped `bookmark` that only resolves on the Mac
  that made it. Other devices show the attachment with "On <device name>" and
  no Open action. `bookmark` and `local_copy_path` are stripped from synced
  data; a new `blob_sha256` field carries the content address.

## 5. Security and backup

- TLS everywhere outside a private LAN; Tailscale HTTPS certificates on the NAS.
- Per-device tokens, revocable; pairing code at least 12 characters, kept in
  the server's `.env`.
- Postgres data and blobs on a ZFS dataset with periodic snapshots; nightly
  `pg_dump` to a second dataset. Local daily app backups continue.

## 6. Phases and acceptance

| # | Phase | Done when |
|---|---|---|
| 1 | Server core | Pair, push, pull, status; tests pass against Postgres; image builds; compose stack answers `/health`. **Prototype exists; Docker smoke test and clock guard still open.** |
| 2 | Change capture + device id | Migration v9; every write to a synced table produces one `sync_change` row; applying with the flag set produces none; unit tests per table. |
| 3 | Sync engine | Two in-memory "devices" plus a test server converge after: create, edit, delete, conflicting edits, offline queue, paged pull, stale push. |
| 4 | Settings + first sync | Pair/unpair from the UI; first sync of a populated database verified against a copy of real data; backup taken first. |
| 5 | Attachments | Pasted image on Mac A opens on Mac B; linked files show their origin. |
| 6 | TrueNAS deploy | Compose app installed on the NAS, snapshots and nightly dump configured, both Macs syncing through Tailscale; setup notes written. |

Each phase ships behind the Sync on/off switch (default off), so releases can
continue while sync is unfinished.

## 7. Risks

| Risk | Mitigation |
|---|---|
| First merge of two populated databases goes wrong | Automatic backup before first sync; rehearse on copies of both real databases |
| Wrong device clock decides conflicts | Server clock guard; show a warning when server and device time differ by > 2 min |
| Older app version drops fields it does not know | Apply writes only known columns and never rewrites unknown server data; server keeps the full JSON |
| Triggers miss a table added later | A test enumerates all tables and fails if one is neither synced nor on the never-synced list |
| API key leaks through settings sync | Settings are allow-listed, not block-listed |

## 8. Open decisions

1. Pairing code entry vs. QR code (plan: typed code first).
2. Keep or remove `change_outbox` after sync ships.
3. Whether to move trays out of `setting.work_trays` before or after sync.
