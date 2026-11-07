# TodayFlow

Native macOS task app (SwiftUI + AppKit). The contract is `driver.md` (12 sections).

## Status

Increments 1–8 from `driver.md` §11 are complete and committed:

- Core (entities, use cases, ports), Persistence (GRDB, outbox, FTS), Recognition
  (eleven recognizers + pipeline), Design, Features, Mac composition root,
  TodayFlowAI (OpenAI-compatible client + four AI features), TodayFlowSync (no-op).
- `swift build` is warning-free; `swift test` passes **749 tests**; the XCUITest suite has 22 cases.
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
- v1 is local-only. Sync outbox rows stay pending for the v2 CloudKit engine.

`./scripts/build-app.sh` wraps the executable in a Developer ID-signed `.app`
(hardened runtime). `scripts/package-dmg.sh` notarizes and staples the DMG when
`NOTARY_PROFILE` is set; the 1.9.18 DMG is notarized. Known follow-ups: XCUITests +
performance gates, live Markdown rendering and pasted images in the detail
description.

## Context rules (keep sessions small)
- Never read or search inside: `.build/`, `DerivedData/`, `Pods/`, `*.sqlite`, `*.xcodeproj/project.pbxproj`.
- Read large files in line ranges, or grep for the symbol you need, instead of whole files.
- One focused task per session; commit per increment.
