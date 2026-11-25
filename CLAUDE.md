# TodayFlow

Native macOS task app (SwiftUI + AppKit). The contract is `driver.md` (12 sections).

## Status

Increments 1–8 from `driver.md` §11 are complete and committed:

- Core (entities, use cases, ports), Persistence (GRDB, outbox, FTS), Recognition
  (eleven recognizers + pipeline), Design, Features, Mac composition root,
  TodayFlowAI (OpenAI-compatible client + four AI features), TodayFlowSync (server sync: `SyncClient`, `SyncRunner`).
- `swift build` is warning-free; `swift test` passes **966 tests**; the XCUITest suite has 22 cases.
- Daily database backups (keep 7) and JSON/CSV export are implemented (NFR-09).
- Schema v2 adds an append-only `activity` audit table; GRDB repositories record
  who/when/source-app/location for creates, edits, status, links, drops, reminders.
- UI: cinematic dark/light theme, week strip/day planning, future-row priority/
  start/reorder menus, due-soon pulse + banner, window edge/window docking,
  native main menu, minimize-to-menu-bar restore, working trays, Focus mode,
  week/month Calendar window, per-task reminders, XLSX export, estimates/load
  meter, tags editor, Insights, mini calendar corner pinning, attachment Open With
  and per-attachment descriptions. Pin the panel to another app’s left/right/top/
  bottom edge and follow its window; tray windows tile to the right. Priority pills
  use the priority palette. A task can live in only one tray. Outlook/Mail drops
  are summarized into the new `WorkItem.summary` by Apple Intelligence or an
  OpenAI-compatible endpoint (schema v5). Contacts with groups, vCard/CSV and
  macOS Contacts import, duplicate auto/manual merge, many-to-many task links,
  and contact-card drops that create a task and optionally add/group the contact
  (schema v6). Tray windows follow the panel until the user moves a tray window.
  Jira tickets dragged from the web are recognized by issue key, use the card
  summary as the task title, and keep the Jira URL/metadata. The Today header
  has a folder+ project creator; projects are containers and are excluded from
  Today/Upcoming/Calendar/Insights task counts. Optional first-run AI setup
  offers Apple Intelligence, a 533 MB Qwen3.5 0.8B download through Ollama
  (with disk/memory footprint shown), or skip.
- Design references and the token plan live in `docs/design/todayflow-design.md`.
- Installed official Anthropic skills: `frontend-design`, `theme-factory`;
  Superpowers development skills (`test-driven-development`, `systematic-debugging`,
  `verification-before-completion`, `writing-plans`, review skills).
- Sync (1.9.26, schema v9–v10): triggers record changes in `sync_change`; attachment files
  upload/download as blobs; Settings ▸ Sync pairs
  with the self-hosted server in `Server/` (design `docs/sync/PLAN.md`, status `docs/sync/HANDOFF.md`).
  The old `change_outbox` is left as is.
- Obsidian archive: besides the two-way sync note, `ObsidianArchive` (Core) renders every task,
  project, contact and day as a cross-linked note plus `TodayFlow.base`; `ObsidianSyncController`
  writes only changed files, tracked by `ObsidianArchiveManifest` in setting `obsidian_archive`.
- Obsidian via server: transport `.server` sends REST calls to the paired sync server's
  `/v1/obsidian/…` proxy (`Server/…/ObsidianProxy.swift`) with `X-Obsidian-Target`/`-Authorization`;
  the server stores nothing. Local, REST and MCP are unchanged.

`./scripts/build-app.sh` wraps the executable in a Developer ID-signed `.app`
(hardened runtime). `scripts/package-dmg.sh` notarizes and staples the DMG when
`NOTARY_PROFILE` is set; the 1.9.33 DMG is notarized. Known follow-ups: XCUITests +
performance gates, live Markdown rendering and inline images in the detail
description. ⌘V in a task or New Task window attaches the clipboard (image, file,
link); the Today list and All Tasks have a hide/show filter for tasks in trays.
New tasks start at the top of the current hour and a due time is always after
the start (`TaskSchedule`). The header calendar strip pages by week or month,
with a dot and a top-3 hover list per day. Trays start folded to name + count
chips. View ▸ Task History (⌘9) lists every task newest first with All / Due
today / Past / Completed and a date range. `DueNudgeController` shows an animated
popup as a task crosses 12 h, 5 h and 1 h before due (View ▸ Due-Soon Popups;
`-previewDueNudge 1|5|12` on the command line shows a sample).

## Context rules (keep sessions small)
- Never read or search inside: `.build/`, `DerivedData/`, `Pods/`, `*.sqlite`, `*.xcodeproj/project.pbxproj`.
- Read large files in line ranges, or grep for the symbol you need, instead of whole files.
- One focused task per session; commit per increment.
