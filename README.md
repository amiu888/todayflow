# TodayFlow

A native macOS app that turns anything you drag in — an email, a Teams message, a
Jira ticket, a calendar invite, a PDF, an image, a file, a folder, a URL — into a task
in under five seconds, and keeps the day's tasks visible until every one is done.

Full product spec and project plan: [`driver.md`](./driver.md).

Step-by-step guides with real screenshots and a video walkthrough: [`docs/tutorials`](./docs/tutorials).

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

Verification: `swift build` is warning-free, `swift test` passes **741 tests**, and
the XCUITest suite has twenty-one cases against the real `.app` bundle. Local performance
spot-checks: the Today panel appears in about 273 ms, 5,000 contacts load and search in
about 0.21 s, and the 10,000-item Today query stays under the 500 ms NFR-04 bound. The app also makes a daily
database snapshot (`VACUUM INTO`) and keeps the last 7 in
`Application Support/TodayFlow/Backups/` (NFR-09).

The UI uses a cinematic dark theme (near-black indigo, blue-charcoal surfaces,
sky→royal→violet accent) with a light theme from **View → Appearance**. The week
strip plans future days in place, future rows expose priority/start/reorder
actions, per-task reminders are set from the detail window, due tasks pulse on the
list and in a “Due soon” banner. The pin in the header docks the panel to another
application (left by default, or right/top/bottom), and the panel follows that app’s
front window. Tray windows tile to the right of the panel and of each other; only trays you have not moved follow the panel, while Contacts and other windows stay independent. Dragging uses title bars, so content clicks never nudge a window.

Contacts are first-class: groups, duplicate review, vCard/CSV import, macOS
Contacts sync, and many-to-many links to tasks. A task can have any number of
contacts, and a contact can list every task they are linked to. Working trays are
named staging areas for the tasks in play; drop tasks onto them from the list. Focus mode runs a 25-minute session on one task with pause, +5 min,
and Done. A separate Calendar window switches between week and month planning.
Attachments show up to three source-app icons with a hover overlay; the full list
exports to JSON, CSV, or a real Excel `.xlsx` workbook. Dropping an Outlook or
Apple Mail message creates a task; its email body is summarized into the task’s
new Summary field by Apple Intelligence on-device, or by a configured
OpenAI-compatible cloud/local endpoint. With AI off, no summary is generated.

Design rationale and the competitive references are in
[`docs/design/todayflow-design.md`](./docs/design/todayflow-design.md).

### Where to find things

- **Priority** — click the compact, color-coded **P1–P4** pill on any row; the menu shows every level with a checkmark. Right-click a row for the same menu.
- **Dock to an app** — the **pin** at the top right of the panel. Pick a running application and an edge (Left is the default; Right/Top/Bottom are available), then **Dock**. The panel follows that app’s front window. Click the pin again to change the edge or **Undock**.
- **Contacts** — the **person.2** icon at the top right of the Today panel (or **View → Contacts**, ⌘8). Drag a contact card from macOS Contacts or Outlook into the capture panel (or paste a vCard): it creates a follow-up task and offers to add the person to Contacts. The card has an **Add to Contacts** switch, an optional group, and duplicate resolution — **Merge**, **Use existing**, or **Keep new**. Create contacts and groups, search, import from macOS Contacts (**Sync Contacts**), or import Outlook/other address books exported as vCard/CSV. The import sheet filters by text and by “must have email/phone”; matching emails and phones are merged automatically. The Contacts window opens beside the Today panel and shrinks to 580×420, with a compact header and a stacked detail header at narrow widths. **Duplicates** reviews shared emails/phones and offers auto-merge or merge-into a chosen contact. Open a task to link any number of contacts under its **Contacts** section: click **Add Contact** to pick an existing person, or type a name/email/phone there to create and link one immediately. Matching email/phone reuses the existing contact instead of duplicating it.
- **Microsoft Teams** — drag a chat message, a rich-text chat card, or a Teams link into the Today panel or a tray window. Teams chat text is read from plain text, HTML, or RTF; the first message line becomes the title, the sender is kept, and the full chat is attached as preview text. Works with Teams desktop and Teams web.
- **Jira** — drag a ticket from the Jira web board or issue page into the Today panel, a tray, or the capture sheet. The issue key (`ABC-123`) and summary become the task title, the Jira URL is attached, and the key/project/summary are stored as metadata. Works with Jira Cloud and self-hosted Jira URLs that use `/browse/KEY-123` or `?selectedIssue=KEY-123`; multi-line and HTML drag payloads are handled.
- **Projects** — click the **folder+** icon in the Today header to create a top-level project. Projects group tasks, appear in the project filter and Hierarchy, and never count as Today tasks or progress. In Hierarchy, right-click an epic to add a project beneath it.
- **Email tasks + summary** — drag a message from Outlook or Apple Mail. The task opens with the subject as its title and the message text attached; the detail window’s **Summary** field is filled by Apple Intelligence or your configured AI endpoint. If AI is off, the summary stays empty. Configure it in **Settings → AI**.
- **AI setup / tiny model** — the first launch offers an optional AI choice: Apple Intelligence (0 MB), a tiny local Qwen3.5 0.8B model (533 MB download, about 1.5–2 GB memory while AI runs, served through Ollama), or skip. Nothing is downloaded until you choose. The same setup is available from **Settings → AI → Set up a local model…** and the app menu. With AI off, every core feature still works.
- **Working trays** — Today panel, below the filter row. Tray windows follow the main panel while you drag or dock it; drag a tray window yourself to detach it and keep it where you put it. Drag any task (including Tomorrow & upcoming rows) onto a tray, or right-click → **Add to tray**. Trays hold any number of tasks and accept multi-item drags; drag a chip to another tray to move it. Double-click a tray (or its `…` → **Open tray window**) to open a full tray window with reorder, remove, and drag-and-drop; several tray windows can be open at once. Tray `…` menu: rename, color, insert after, move, delete.
- **Mini calendar / 4 corners** — the **window menu** at the right of the date header, or **View → Mini Calendar** (⌘7). Choose Day/Week and **Pin mini calendar → Top Left / Top Right / Bottom Left / Bottom Right**. It stays on every desktop. **View → Show Windows on All Desktops** extends that to every window.
- **Show windows on all desktops** — **View → Show Windows on All Desktops**.
- **Calendar** — **View → Calendar** (⌘5): week/month boards; drag a task onto a day to reschedule.
- **Insights / weekly review** — **View → Insights** (⌘6).
- **Focus mode** — hover a task and click the scope icon, or right-click → **Focus for 25 minutes**.
- **Reminders** — open a task; the Reminder row is below the dates.
- **Estimates + load meter** — open a task → **Estimate**; the meter appears under Today’s progress when estimates exist.
- **Tags** — open a task; the tag row is under the status/priority pills.
- **Excel export** — **File → Export Excel…** (also JSON/CSV).
- **Attachments** — open a task; each object has its own description field. Double-click to open in its native app (Excel/Preview/etc.). Outlook email attachments reopen in Outlook; Mail messages reopen in Mail. Right-click for **Open**, **Open With…**, Quick Look, Reveal.
- **Move a task** — use the up/down chevrons on the row, right-click → Move up/down, or ⌥↑/⌥↓.
- **Docking** — **View → Dock to Edges** snaps floating windows to screen and other-window edges; the header **pin** attaches to a specific app window and edge.
- **Appearance** — **View → Appearance** (Dark / Light / Follow System).


Every task keeps an append-only activity log: creation, edits, status/priority/date
changes, reorder/reparent, completion/reopen, link add/remove, and attachment add/
remove, including the dropping app, file path/URL, actor, and timestamp. It is
visible at the bottom of the task detail window.

Distribution status:

- Developer ID signing, hardened runtime, and **notarization + stapling** are done for
  the 1.9.13 DMG. Verify with `xcrun stapler validate` and `spctl -a -vvv -t install`.
- Broader XCUITest coverage (drag/drop, trays, calendar, focus) and the NFR-01…05
  performance gates remain follow-ups.
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
runtime). `scripts/package-dmg.sh` builds a signed DMG, notarizes and staples it
when `NOTARY_PROFILE` is set, and writes the SHA-256 checksum **after** stapling
(stapling changes the DMG).

One-time notarytool setup:

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
