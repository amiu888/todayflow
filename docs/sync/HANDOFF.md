# TodayFlow Sync — Handoff

For whoever picks this up next. Read `PLAN.md` first; this file says where
things stand and how to continue. Updated 2026-11-19.

Deployment specifics for a real NAS (addresses, paths, accounts) are never
committed: they live in `Server/deploy.env` (template `deploy.env.example`)
and, for notes, `docs/sync/*.local.md` (ignored by git).

## Where things stand

| Item | State |
|---|---|
| Design | `docs/sync/PLAN.md`; media choices in `MEDIA-OPTIONS.md`. |
| Server | `Server/`: Hummingbird 2 + Postgres 17. Multiple users, pairing codes and device tokens stored as hashes, admin web page (users, devices, backups, Back up now), streaming file store (≤ 1 GB per file, stored once per user), unused files released after 30 days. Schema v3. 34 tests against Postgres. |
| Deployment | Installed on a TrueNAS SCALE 25.04 NAS as a custom app with `Server/deploy.sh`. |
| App | 1.9.26. Schema v9 (change tracking: `sync_change`/`sync_flag`/`sync_state`, 30 triggers on 10 tables) and v10 (attachment `blob_sha256`/`blob_size`, `sync_blob_skip`). `SyncStore` (Persistence), `SyncClient`/`SyncRunner` (Sync), `SyncController` (Mac), Settings ▸ Sync, header badges for server and Obsidian sync. |

## How sync works

- Every insert/update/delete on a synced table is recorded by a trigger in
  `sync_change`; remote changes are applied with `sync_flag.applying = 1`, so
  they never echo back.
- A round: pull pages → delete unused downloaded copies → download files up
  to 10 MB → upload new files → push rows. Newest `changed_at` wins on the
  server and locally.
- Pairing backs up the database to `Backups/before-sync-*.sqlite`, marks all
  rows pending, and leaves sync off until switched on. Rounds run every 10 s,
  on wake and on Sync Now.
- Files: SHA-256 named on the server; downloaded copies in
  `Attachments/Synced/<sha>/<name>` (local-only `local_copy_path`); bigger
  files download when opened; bookmarks never leave the Mac.
- Settings are not synced (work hours, trays, AI keys).

## Tests

- App: `swift test` at the repo root (844 tests).
- Server: start Postgres (`docker run -d --name todayflow-test-pg -e
  POSTGRES_USER=todayflow -e POSTGRES_PASSWORD=test -e POSTGRES_DB=todayflow
  -p 55432:5432 postgres:17-alpine`), then `cd Server && TEST_PGPORT=55432
  swift test`. Without `TEST_PGPORT` the suite is skipped.
- Live (app against a real server): run `Server/.build/debug/TodayFlowServer`
  with `PORT=18787` against a scratch Postgres, `adduser E2E`, then
  `TODAYFLOW_E2E_URL=http://127.0.0.1:18787 TODAYFLOW_E2E_CODE=<code>
  [TODAYFLOW_E2E_DB=<copy of a database>] swift test --filter Live`.

## Facts about the app

- `change_outbox` (v1) is incomplete and left as is; sync uses triggers.
- `device_id` columns hold `"local"`; the server tracks devices itself.
- Trays are one JSON value in `setting.work_trays`, not a table.
- `setting.ai_endpoint` can contain an API key — never sync it.
- `search_index` (FTS5) is kept by triggers, so applied rows are indexed.
- Shipped migrations are never edited; the next app migration is v11.
- Database: `~/Library/Application Support/TodayFlow/todayflow.sqlite`
  (WAL), daily backups in `Backups/` (7 kept).

## Not done

- Tailscale HTTPS for use away from home (plain HTTP only on the LAN).
- Media options 3–5 in `MEDIA-OPTIONS.md` (storage limit per Mac, media
  backup to a second disk, storage on the admin page).
- Encryption at rest.

## Working rules for this repo

- `swift test` stays green and `swift build` warning-free. Commit per increment.
- Release: bump `Resources/Info.plist` (version + build) and the version in
  `Sources/TodayFlowCore/ObsidianMCP.swift`; `./scripts/build-app.sh`;
  `NOTARY_PROFILE=todayflow ./scripts/package-dmg.sh`; `gh release create
  vX.Y.Z` with the DMG and `.sha256`. A notarization 403 means Apple has a new
  agreement pending.
- Never test sync against the real database. Copy it first.
- Before committing, scan for passwords, IPs, pairing codes and NAS details.
- The owner wants designs and plans confirmed before anything is built or
  published.
