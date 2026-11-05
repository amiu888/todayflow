# TodayFlow

Native macOS task app (SwiftUI + AppKit). The contract is `driver.md` (12 sections).

## Status

Increments 1–8 from `driver.md` §11 are complete and committed:

- Core (entities, use cases, ports), Persistence (GRDB, outbox, FTS), Recognition
  (eleven recognizers + pipeline), Design, Features, Mac composition root,
  TodayFlowAI (OpenAI-compatible client + four AI features), TodayFlowSync (no-op).
- `swift build` is warning-free; `swift test` passes **560 tests**; nine XCUITests pass.
- Daily database backups (keep 7) and JSON/CSV export are implemented (NFR-09).
- Schema v2 adds an append-only `activity` audit table; GRDB repositories record
  who/when/source-app/location for creates, edits, status, links, drops, reminders.
- UI: cinematic dark/light theme, week strip/day planning, future-row priority/
  start/reorder menus, due-soon pulse + banner, window edge/window docking,
  native main menu, minimize-to-menu-bar restore, working trays, Focus mode,
  week/month Calendar window, per-task reminders, XLSX export, estimates/load
  meter, tags editor, Insights, mini calendar corner pinning, attachment Open With
  and per-attachment descriptions.
- Design references and the token plan live in `docs/design/todayflow-design.md`.
- Installed official Anthropic skills: `frontend-design`, `theme-factory`;
  Superpowers development skills (`test-driven-development`, `systematic-debugging`,
  `verification-before-completion`, `writing-plans`, review skills).
- v1 is local-only. Sync outbox rows stay pending for the v2 CloudKit engine.

`./scripts/build-app.sh` wraps the executable in a local ad-hoc-signed `.app`
(Info.plist + Dock icon). Known follow-ups before a signed release: Developer ID,
hardened runtime, notarization, XCUITests + performance gates, live Markdown
rendering and pasted images in the detail description.

## Context rules (keep sessions small)
- Never read or search inside: `.build/`, `DerivedData/`, `Pods/`, `*.sqlite`, `*.xcodeproj/project.pbxproj`.
- Read large files in line ranges, or grep for the symbol you need, instead of whole files.
- One focused task per session; commit per increment.
