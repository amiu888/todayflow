# TodayFlow

Native macOS task app (SwiftUI + AppKit). The contract is `driver.md` (12 sections).

## Status

Increments 1–8 from `driver.md` §11 are complete and committed:

- Core (entities, use cases, ports), Persistence (GRDB, outbox, FTS), Recognition
  (eleven recognizers + pipeline), Design, Features, Mac composition root,
  TodayFlowAI (OpenAI-compatible client + four AI features), TodayFlowSync (no-op).
- `swift build` is warning-free; `swift test` passes **501 tests**.
- v1 is local-only. Sync outbox rows stay pending for the v2 CloudKit engine.

Known follow-ups before a signed release: an `.app` bundle/Info.plist/entitlements,
Dock icon, XCUITests + performance gates, live Markdown rendering and pasted images
in the detail description.

## Context rules (keep sessions small)
- Never read or search inside: `.build/`, `DerivedData/`, `Pods/`, `*.sqlite`, `*.xcodeproj/project.pbxproj`.
- Read large files in line ranges, or grep for the symbol you need, instead of whole files.
- One focused task per session; commit per increment.
