# TodayFlow

A native macOS app that turns anything you drag in — an email, a Teams message, a
calendar invite, a PDF, an image, a file, a folder, a URL — into a task in under five
seconds, and keeps the day's tasks visible until every one is done.

Full product spec and project plan: [`driver.md`](./driver.md).

## Architecture

Clean Architecture (ports and adapters) in Swift 6. A pure-Swift core holds all
business rules; UI, storage, AI and OS services plug in through protocols. Each
directory below maps to a logical package in `driver.md` §5 — the core depends on
nothing, so a new device is a new shell and a new database is a new adapter.

| Target | Responsibility | Depends on |
| --- | --- | --- |
| `TodayFlowCore` | Entities, use cases, repository ports (Foundation only) | — |
| `TodayFlowPersistence` | GRDB repositories, migrations, FTS, outbox | Core |
| `TodayFlowSync` | Outbox + sync engine (Noop in v1) | Core |
| `TodayFlowRecognition` | Drop parsing: UTType, Outlook, Teams, URLs | Core |
| `TodayFlowAI` | OpenAI-compatible client + prompts | Core |
| `TodayFlowDesign` | Colors, icons, animations, shared components | Core |
| `TodayFlowFeatures` | SwiftUI features: Today, Capture, Detail, Hierarchy, Settings | Core, Design |
| `TodayFlowMac` | Composition root, `NSPanel`, `NSStatusItem`, hotkey, notifications | all of the above |

## Status

Build increments land in the order from `driver.md` §11. Progress:

- [x] **1. TodayFlowCore** — entities, `WorkCalendar`, `FractionalIndex`, `UUIDv7`,
      use cases, repository ports + in-memory adapters, tests
- [ ] 2. TodayFlowPersistence — migration v1, GRDB records, repositories, outbox, FTS
- [ ] 3. TodayFlowRecognition — `ObjectRecognizer` pipeline + fixtures
- [ ] 4. TodayFlowDesign — priority colors, icons, progress ring, animations
- [ ] 5. TodayFlowFeatures — Today list → Capture → Detail → Hierarchy → Settings
- [ ] 6. TodayFlowMac — composition root, panel, menu bar, hotkey, notifications
- [ ] 7. TodayFlowAI — OpenAI-compatible client + the four AI features
- [ ] 8. TodayFlowSync — `NoopSyncEngine`

## Building

```sh
swift build          # build all targets
swift test           # run all tests
```

Requires Swift 6 / Xcode 16+. Minimum deployment: macOS 14 Sonoma.

## Conventions

- Swift 6 language mode, strict concurrency, no warnings.
- Conventional Commits; one increment = one feature slice + tests + green build.
- Reference requirement IDs (FR-xx, NFR-xx) in commit messages and test names.
- ADRs in [`docs/adr`](./docs/adr).
