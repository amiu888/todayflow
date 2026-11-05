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
| `TodayFlowSync` | Outbox + sync engine (Noop in v1) | Core, Persistence |
| `TodayFlowRecognition` | Drop parsing: UTType, Outlook, Teams, URLs | Core |
| `TodayFlowAI` | OpenAI-compatible client + prompts | Core |
| `TodayFlowDesign` | Colors, icons, animations, shared components | Core |
| `TodayFlowFeatures` | SwiftUI features: Today, Capture, Detail, Hierarchy, Settings | Core, Design |
| `TodayFlowMac` | Composition root, `NSPanel`, `NSStatusItem`, hotkey, notifications | all of the above |

## Status

Build increments land in the order from `driver.md` §11. All eight are complete:

- [x] **1. TodayFlowCore** — entities, `WorkCalendar`, `FractionalIndex`, `UUIDv7`,
      use cases, repository ports + in-memory adapters
- [x] **2. TodayFlowPersistence** — migration v1, GRDB records, repositories, outbox, FTS
- [x] **3. TodayFlowRecognition** — eleven recognizers, materializer, enricher, pipeline
- [x] **4. TodayFlowDesign** — priority colors, icons, progress ring, motion, tokens
- [x] **5. TodayFlowFeatures** — Today, Capture, Detail, Hierarchy, Settings, end-of-day
      review, Upcoming, Completed, project filter, undo, drag reorder, JSON/CSV export,
      and a full per-task activity/audit log
- [x] **6. TodayFlowMac** — composition root, floating panel, menu bar, slim bar,
      global hotkey, drag-and-drop + paste, notifications, Quick Look / open / reveal
- [x] **7. TodayFlowAI** — OpenAI-compatible client (JSON-schema fallback, retries,
      SSE streaming, prompt resources), smart capture, breakdown, plan, ask, Fetch models
- [x] **8. TodayFlowSync** — `NoopSyncEngine` that leaves the outbox pending for v2

Verification: `swift build` is warning-free, `swift test` passes **547 tests**, and
the five XCUITests pass against the real `.app` bundle. The app also makes a daily
database snapshot (`VACUUM INTO`) and keeps the last 7 in
`Application Support/TodayFlow/Backups/` (NFR-09).

The UI uses a cinematic dark theme (near-black indigo, blue-charcoal surfaces,
sky→royal→violet accent) with a light theme from **View → Appearance**. The week
strip plans future days in place, future rows expose priority/start/reorder
actions, per-task reminders are set from the detail window, due tasks pulse on the
list and in a “Due soon” banner, and floating windows dock to screen/window edges.

Working trays are named staging areas for the tasks in play; drop tasks onto them
from the list. Focus mode runs a 25-minute session on one task with pause, +5 min,
and Done. A separate Calendar window switches between week and month planning.
Attachments show up to three source-app icons with a hover overlay; the full list
exports to JSON, CSV, or a real Excel `.xlsx` workbook.

Design rationale and the competitive references are in
[`docs/design/todayflow-design.md`](./docs/design/todayflow-design.md).

### Where to find things

- **Working trays** — Today panel, below the filter row. Drag any task (including Tomorrow & upcoming rows) onto a tray, or right-click → **Add to tray**. Tray `…` menu: rename, color, insert after, move, delete.
- **Mini calendar / 4 corners** — the **window menu** at the right of the date header, or **View → Mini Calendar** (⌘7). Choose Day/Week and **Pin mini calendar → Top Left / Top Right / Bottom Left / Bottom Right**. It stays on every desktop. **View → Show Windows on All Desktops** extends that to every window.
- **Show windows on all desktops** — **View → Show Windows on All Desktops**.
- **Calendar** — **View → Calendar** (⌘5): week/month boards; drag a task onto a day to reschedule.
- **Insights / weekly review** — **View → Insights** (⌘6).
- **Focus mode** — hover a task and click the scope icon, or right-click → **Focus for 25 minutes**.
- **Reminders** — open a task; the Reminder row is below the dates.
- **Estimates + load meter** — open a task → **Estimate**; the meter appears under Today’s progress when estimates exist.
- **Tags** — open a task; the tag row is under the status/priority pills.
- **Excel export** — **File → Export Excel…** (also JSON/CSV).
- **Attachments** — open a task; each object has its own description field. Double-click to open in its native app (Excel/Preview/etc.), right-click for **Open**, **Open With…**, Quick Look, Reveal.
- **Move a task** — use the up/down chevrons on the row, right-click → Move up/down, or ⌥↑/⌥↓.
- **Docking** — **View → Dock to Edges**; windows snap to screen and other-window edges.
- **Appearance** — **View → Appearance** (Dark / Light / Follow System).


Every task keeps an append-only activity log: creation, edits, status/priority/date
changes, reorder/reparent, completion/reopen, link add/remove, and attachment add/
remove, including the dropping app, file path/URL, actor, and timestamp. It is
visible at the bottom of the task detail window.

Known follow-ups before shipping a signed build (outside the eight build increments):

- Developer ID signing, hardened-runtime entitlements, and notarization for distribution
  (the local bundle script does ad-hoc signing).
- Broader XCUITest coverage (drag/drop, trays, calendar, focus) and the NFR-01…05
  performance gates.
- Live Markdown rendering and pasted-image attachments inside the detail description.
- CloudKit sync (v2, per `driver.md` §6); v1 is intentionally local-only.

## Building

```sh
swift build          # build all targets
swift test           # run all tests

./scripts/build-app.sh
open build/TodayFlow.app

./scripts/run-ui-tests.sh   # real XCUITest against the built .app
```

`scripts/build-app.sh` wraps the SwiftPM executable in a `.app` bundle and signs
it with the first **Developer ID Application** identity in the keychain (hardened
runtime). `scripts/package-dmg.sh` builds a signed DMG plus SHA-256 checksum.

Notarization needs an Apple Developer account and a notarytool keychain profile:

```sh
xcrun notarytool store-credentials todayflow \
  --apple-id "you@example.com" --team-id XC9C9QZ6W8
NOTARY_PROFILE=todayflow ./scripts/package-dmg.sh
```

Requires Swift 6 / Xcode 16+. Minimum deployment: macOS 14 Sonoma.

## Conventions

- Swift 6 language mode, strict concurrency, no warnings.
- Conventional Commits; one increment = one feature slice + tests + green build.
- Reference requirement IDs (FR-xx, NFR-xx) in commit messages and test names.
- ADRs in [`docs/adr`](./docs/adr).
