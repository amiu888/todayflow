# TodayFlow — macOS Daily Task App: Product Spec & Project Plan

Nov 2, 2026 · @amiu

## 1. Overview

TodayFlow is a native macOS app that turns anything a user drags in (an email, a Teams message, a calendar invite, a PDF, an image, a file, a folder, a URL) into a task in under five seconds, and keeps the day's tasks visible until every one is done. "TodayFlow" is a working name.

**Problem.** Daily work arrives through many channels. Tracking it means copying details into a task tool by hand, so small items get lost and the day ends with unfinished work nobody noticed.

**Product goals**

1. **Capture in one gesture.** Drop any object on the app; a quick-add sheet opens with everything prefilled. The user types at most a title.
2. **Clear the day.** The main screen shows only today's tasks, with a live progress ring (done vs remaining) and gentle reminders before end of business.
3. **Stay out of the way.** A compact floating panel and a menu bar item, never a full-screen app.
4. **Organize when wanted, not required.** Epics → Projects → Tasks → Subtasks exist, but every level can stand alone.
5. **Respect order.** Tasks can be chained (A must finish before B) by dragging one task onto another.
6. **AI-ready.** Any OpenAI-compatible LLM (local such as Ollama or LM Studio, or cloud) can suggest titles, summarize dropped content, break tasks into subtasks, and plan the day.
7. **Built to grow.** Architecture and data layer ready for iPhone, iPad, Apple Watch and a cloud database later.

**Target user.** An office worker on Microsoft 365 (Outlook, Teams) and macOS who handles 5–30 small tasks a day and wants to finish them, not manage them.

**Non-goals for v1.** Team collaboration and sharing, Gantt charts, time tracking/billing, two-way sync with Jira or Outlook tasks, Windows support.

## 2. Core concepts and domain model

Every work item is one `WorkItem` record with a `kind` (epic, project, task, subtask) and an optional `parentId`, so any item can exist alone, be attached to a parent later, or be detached without data loss.

**Hierarchy rules**

| Kind | Allowed parent | Allowed children | Can stand alone |
| --- | --- | --- | --- |
| Epic | none | Projects (0..n) | Yes |
| Project | Epic (0..1) | Tasks (0..n) | Yes |
| Task | Project (0..1) | Subtasks (0..n) | Yes |
| Subtask | Task (0..1) | none | Yes (shown as a task) |

- Deleting a parent never deletes children by default; children become unparented. A "delete with children" option is explicit.
- Moving an item between parents is drag and drop in the hierarchy view, validated by the rules above.
- Progress rolls up: a project's progress = done tasks / all tasks; an epic's = average of its projects, weighted by task count.

**Other entities**

- **Attachment** — an object dropped on or added to a task: file, folder, email, calendar event, Teams message, URL, image, text snippet. A task has 0..n attachments. Each stores its type, display name, icon type, a reference (bookmark, URL, or message id) and an optional cached preview.
- **Link** — a typed relation between two work items, independent of the hierarchy. Types: `blocks` (sequence: A must be done before B) and `relatesTo` (informational).
- **Dependency chain** — `blocks` links form a one-way linked list per chain: each task has at most one direct predecessor and one direct successor in a chain. Cycles are rejected. A blocked task shows a lock and cannot be marked done until its predecessor is done (overridable with a confirmation).
- **Action** — a checklist item inside a task ("Reply to Anna", "Attach budget"). Lighter than a subtask: no dates, no priority.
- **Reminder** — a scheduled notification on a task (default: 30 minutes before end date) plus the app-wide end-of-day nudges.
- **WorkCalendar** — user settings for business hours (default 09:00–17:00, Mon–Fri) used to compute default end dates.

**Task fields**

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| title | string, 1–200 chars | inferred from dropped object | required |
| description | rich text (Markdown) | empty | optional |
| actions | ordered checklist | empty |  |
| startAt | date-time | time of drop / creation |  |
| endAt | date-time | today's end of business (e.g. 17:00) | if created after end of business → next business day's end |
| priority | enum: P1 Urgent, P2 High, P3 Normal, P4 Low | P3 Normal |  |
| status | enum: To do, In progress, Blocked, Done, Cancelled | To do | Blocked is derived from links |
| displayOrder | fractional index (string) | top of list | supports manual drag reordering |
| parentId | UUID? | none |  |
| tags | \[string\] | empty |  |
| completedAt | date-time? | none | set when marked done |

## 3. Functional requirements

Requirements carry IDs (FR-xx) so code, tests and tickets can reference them.

**Capture**

- **FR-01 Drop anywhere.** The main panel, the menu bar icon and the Dock icon all accept drops. Multiple objects dropped at once → one task with all of them attached (default) or one task per object (hold ⌥ while dropping).
- **FR-02 Quick-add sheet.** On drop, a small sheet opens within 300 ms with: title (prefilled when inferable, text selected for overwrite), description (optional, collapsed), start (now), end (today's end of business), priority (P3), the attachment chips with icons, and an optional parent picker. Return saves; Esc cancels.
- **FR-03 Title inference.** Email → subject; calendar event → event title; Teams message → first line of message; file → file name without extension; URL → page title (fetched async) or domain; image → file name, or LLM caption when AI is enabled; plain text → first line (max 80 chars).
- **FR-04 Drop onto an existing task** adds the object as an attachment to that task instead of creating a new one.
- **FR-05 Keyboard capture.** Global hotkey (default ⌃⌥Space) opens the quick-add sheet empty. Natural-language dates in the title ("call Bob tomorrow 3pm") are parsed with `NSDataDetector`.
- **FR-06 Paste.** ⌘V on the panel behaves like a drop of the clipboard contents.

**Today view (main screen)**

- **FR-10** Shows tasks where startAt ≤ end of today and status is not Done/Cancelled, plus overdue tasks (pinned at top, red marker), plus tasks completed today (collapsed "Done today" section).
- **FR-11 Sorting.** Sort menu: Display order (default), Priority then due date, Due date then priority. Choice is persisted.
- **FR-12 Manual order.** Drag a row up or down, or ⌥↑/⌥↓, to change displayOrder. Manual reordering switches the sort to Display order.
- **FR-13 Progress header.** Ring and counters: done / total today, remaining, overdue, and time left until end of business.
- **FR-14 Complete.** Click the circle, press Space, or swipe right (trackpad) to mark done. Undo available for 5 s (⌘Z thereafter).
- **FR-15 Filters.** Quick filter chips: All, Blocked, P1/P2 only, by project. Search (⌘F) across titles, descriptions and attachment names.
- **FR-16 Other views.** Upcoming (next 7 days), All items (hierarchy tree of Epics → Projects → Tasks), and Completed history.

**Task detail and editor**

- **FR-20** Detail window opens on double-click or Return. Layout follows a Jira-style issue page: title, status and priority pills, dates, parent breadcrumb, description editor, actions checklist, subtasks, attachments grid, links (blocked by / blocks / related), activity log.
- **FR-21 Description editor** supports Markdown shortcuts (headings, bold, lists, checkboxes, code, links) with live rendering; pasted images become attachments.
- **FR-22 Inline edits** everywhere: click any field to edit; dates use a compact picker with shortcuts (Today EOB, Tomorrow EOB, +1h, Next Monday).
- **FR-23 Attachments** open with the default app (or Outlook/Teams deep link); Quick Look preview with Space; "Reveal in Finder" for files and folders.

**Dependencies**

- **FR-30** Drag task A onto task B in the list and choose "A must be done before B" (the drop popover also offers "Make B a subtask of A" and "Link as related").
- **FR-31** The list draws a thin connector between chained tasks and shows a lock on blocked ones. Completing A unlocks B with an animation.
- **FR-32** Removing a task from the middle of a chain reconnects its predecessor to its successor (linked-list behaviour) after confirmation.

**Reminders and presence**

- **FR-40 Menu bar item** shows remaining count (e.g. "4") and a mini progress ring; click opens a compact today list.
- **FR-41 Floating panel** can be pinned on top, docked to a screen edge, or collapsed to a slim bar showing only the progress ring and next task.
- **FR-42 Nudges.** Local notifications at configurable times (defaults: 2 h and 30 min before end of business) when tasks remain, plus each task's own reminder. Notification actions: Mark done, Snooze 15 min, Move to tomorrow.
- **FR-43 End-of-day review.** At end of business, a sheet lists unfinished tasks with one-click Move to tomorrow / Pick a date / Done / Cancel.
- **FR-44 Focus mode.** Respects macOS Focus; no nudges during Do Not Disturb unless P1.

## 4. UI/UX specification

The UI is the product: one narrow panel (default 360 × 640 pt, min 300 × 420) that answers "how is my day going?" in one glance and accepts a drop at any moment.

**Design principles**

1. One glance: progress ring + remaining count are always visible, even when collapsed.
2. One gesture to capture, one click to complete.
3. Progressive disclosure: details live in the detail window, not the list.
4. Native macOS look (SwiftUI, SF Symbols, system materials, light/dark, accent color), full keyboard control, VoiceOver labels on every control.

**Main panel layout (wireframe)**

```text
┌──────────────────────────────────────┐
│  ◔ 5 / 9 done     4 left · 2h 10m    │  ← progress header (ring animates)
│  [All] [Blocked] [P1–P2]   Sort ▾  🔍 │  ← filter chips + sort
├──────────────────────────────────────┤
│ ⚠ OVERDUE                            │
│ ○ 🔴 Send Q3 report      📊 ✉   9:30 │
│ TODAY                                │
│ ○ 🟠 Reply to Anna       ✉     11:00 │
│ ○ 🟡 Review contract     📕    17:00 │
│ ┊                                    │  ← chain connector
│ 🔒 🟡 Sign contract      📕    17:00 │  ← blocked until above is done
│ ○ ⚪ Book travel         🔗    17:00 │
│ ▸ Done today (5)                     │
├──────────────────────────────────────┤
│   ⤓  Drop emails, files, links here  │  ← drop hint (expands on drag-over)
└──────────────────────────────────────┘
```

Each row: completion circle, priority dot (P1 red, P2 orange, P3 yellow, P4 grey), title (1 line, truncated), up to 3 attachment icons (+n), due time (red when overdue), project color strip on the left edge when parented. Hover reveals quick actions: priority, move to tomorrow, open.

**Window modes**

| Mode | Size | Behaviour |
| --- | --- | --- |
| Panel | 360 × 640 pt | Floating `NSPanel`, optional always-on-top, snaps to screen edges |
| Slim bar | 360 × 44 pt | Ring + next task only; expands on hover or drag-over |
| Menu bar | popover 340 × 480 pt | Today list, quick add, open panel |
| Detail window | 720 × 640 pt | Standard window, one per task or tabbed |

**Quick-add sheet (on drop)**

```text
┌ New task ─────────────────────────────┐
│ Title  [Re: Q3 budget review_______]  │  ← prefilled, selected
│ + Add description                     │
│ 📅 Today 10:42 → Today 17:00   P3 ▾   │
│ 📎 ✉ Re: Q3 budget review (Outlook)   │
│ Project: None ▾          [Cancel][Add]│
└───────────────────────────────────────┘
```

**Drag-and-drop feedback**

- Drag-over the panel: the drop zone grows, border pulses in accent color, and shows the recognized type ("Outlook email").
- Drag a task onto another: the target row highlights and a popover offers Before/Subtask/Related.
- Reorder: rows part with a spring animation; a 2 pt insertion line shows the target.

**Motivation and animation** (all respect "Reduce motion")

- Completing a task: circle fills with a checkmark draw-on (250 ms), row slides into "Done today", ring advances with a spring.
- Streak and pace: a small "on pace / behind pace" indicator compares done-rate to time left in the day.
- Milestones: subtle confetti burst at 50% and 100% of the day; at 100% the header shows "Day cleared" with the finish time.
- Unlock: when a predecessor completes, the next task's lock opens and the row glows once.
- No guilt mechanics: overdue tasks are marked, never shamed; animations are short and skippable.

**Attachment icons**

| Type (detected by UTType / source) | Icon |
| --- | --- |
| Outlook / Mail email (.eml, .msg, message URL) | envelope, Outlook badge when from Outlook |
| Calendar event (.ics, Outlook event) | calendar with event date |
| Teams message / meeting link | Teams-style chat bubble |
| PDF | red PDF document |
| Excel (.xlsx, .xls, .csv) | green spreadsheet |
| Word (.docx, .doc) | blue document |
| PowerPoint (.pptx) | orange slides |
| Image (png, jpg, heic, screenshot) | thumbnail preview |
| Folder | system folder icon |
| URL | site favicon, globe fallback |
| Other file | the file's system icon from `NSWorkspace` |

Use the real system icon (`NSWorkspace.shared.icon(for:)`) for files where available, with a bundled SF Symbol fallback set so iOS/watchOS render the same types consistently.

## 5. Architecture

Use Clean Architecture (ports and adapters) in Swift: a pure-Swift core holds all business rules, and UI, storage, AI and OS services plug into it through protocols. That is what lets iPhone, iPad, Watch and a cloud database arrive later without rewriting logic.

&#91;embedded content: architecture · 4 layers, dependencies point at the core\]

Features and adapters both depend on the core; the core depends on nothing, so a new device is a new shell and a new database is a new adapter.

**Technology choices**

| Concern | Choice | Why |
| --- | --- | --- |
| Language | Swift 6, strict concurrency | Data-race safety, shared across all Apple platforms |
| UI | SwiftUI, with AppKit bridges (`NSPanel`, `NSStatusItem`, drag pasteboard) | Shared views with iOS/watchOS; AppKit only where macOS needs it |
| State | `@Observable` view models, MVVM per feature | Simple, testable, no third-party framework needed |
| Concurrency | async/await, actors for repositories and sync | Keeps the UI thread free; drops feel instant |
| Database | SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift), WAL mode, FTS5 | Sub-millisecond queries, full-text search, works on every Apple OS, migrations, observation |
| Dependency injection | Constructor injection through a `AppEnvironment` container | No hidden singletons; easy test doubles |
| Notifications | `UserNotifications` | Same API on macOS, iOS, watchOS |
| Logging | `os.Logger` with categories | Native, privacy-aware |
| Min OS | macOS 14 Sonoma (iOS 17 / watchOS 10 later) | `@Observable` and modern SwiftUI drag APIs |

**Swift package layout** (one Xcode workspace, local Swift packages)

```text
TodayFlow/
├─ Apps/
│  ├─ TodayFlowMac/            # macOS app target: panel, menu bar, AppKit bridges
│  ├─ TodayFlowiOS/            # later
│  └─ TodayFlowWatch/          # later
├─ Packages/
│  ├─ TodayFlowCore/           # entities, use cases, ports (no imports beyond Foundation)
│  ├─ TodayFlowPersistence/    # GRDB repositories, migrations, FTS
│  ├─ TodayFlowSync/           # outbox + sync engine (stub in v1)
│  ├─ TodayFlowRecognition/    # drop parsing: UTType, Outlook, Teams, URLs
│  ├─ TodayFlowAI/             # OpenAI-compatible client + prompts
│  ├─ TodayFlowFeatures/       # SwiftUI features: Today, Capture, Detail, Hierarchy, Settings
│  └─ TodayFlowDesign/         # colors, icons, animations, shared components
└─ Tests/                      # per-package unit tests + UI tests
```

**Rules**

- `TodayFlowCore` imports only Foundation. No SwiftUI, GRDB or network code.
- Features talk to use cases, never to repositories directly.
- Every port has a production adapter and an in-memory adapter for tests and previews.
- Platform-specific code (AppKit, `NSPanel`) lives only in the app target or behind `#if os(macOS)`.

## 6. Data layer

Store everything in one local SQLite database (GRDB, WAL mode, FTS5 full-text index) behind repository protocols, and design every table for sync from day one: UUIDv7 ids, timestamps, soft deletes, and an outbox of changes.

**Why SQLite + GRDB over the alternatives**

| Option | Verdict | Reason |
| --- | --- | --- |
| SQLite + GRDB | Chosen | Fastest local option for this size of data, FTS5 text search, explicit migrations, runs on macOS/iOS/watchOS, schema maps 1:1 to Postgres later |
| SwiftData / Core Data | Rejected | Less control over schema and migrations; CloudKit-only sync path |
| Realm | Rejected | Device Sync service deprecated; extra dependency |
| Plain JSON / Markdown files | Rejected | No indexed queries, no transactions; slow for search and sorting |

**Sync-ready conventions (every table)**

- `id` TEXT primary key, UUIDv7 (time-ordered, globally unique; safe to merge across devices).
- `createdAt`, `updatedAt` as ISO-8601 UTC; `deletedAt` for soft delete (tombstone).
- `version` INTEGER incremented on every write (optimistic concurrency, conflict detection).
- `deviceId` of the last writer.
- All writes go through repositories, which also append a row to `change_outbox` in the same transaction.

**Schema (v1)**

```sql
CREATE TABLE work_item (
  id TEXT PRIMARY KEY,               -- UUIDv7
  kind TEXT NOT NULL CHECK (kind IN ('epic','project','task','subtask')),
  parent_id TEXT REFERENCES work_item(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description_md TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'todo',      -- todo|in_progress|done|cancelled
  priority INTEGER NOT NULL DEFAULT 3,      -- 1 urgent .. 4 low
  start_at TEXT, end_at TEXT,               -- ISO-8601 UTC
  completed_at TEXT,
  display_order TEXT NOT NULL,              -- fractional index, e.g. 'a0', 'a0V'
  color TEXT, tags_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
  version INTEGER NOT NULL DEFAULT 1, device_id TEXT NOT NULL
);
CREATE INDEX idx_item_today ON work_item(deleted_at, status, end_at);
CREATE INDEX idx_item_parent ON work_item(parent_id);

CREATE TABLE action_item (           -- checklist inside a task
  id TEXT PRIMARY KEY, work_item_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
  text TEXT NOT NULL, is_done INTEGER NOT NULL DEFAULT 0, sort_order TEXT NOT NULL,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE attachment (
  id TEXT PRIMARY KEY, work_item_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
  type TEXT NOT NULL,          -- file|folder|email|calendar_event|teams_message|url|image|text
  uti TEXT,                    -- e.g. com.adobe.pdf, org.openxmlformats.spreadsheetml.sheet
  display_name TEXT NOT NULL,
  source_app TEXT,             -- outlook|mail|teams|finder|safari|...
  reference TEXT NOT NULL,     -- URL, deep link, message-id, or file path
  bookmark BLOB,               -- security-scoped bookmark for files/folders
  local_copy_path TEXT,        -- copied into app container when original is transient (.msg, .eml, images)
  metadata_json TEXT NOT NULL DEFAULT '{}',  -- sender, received date, page count, size...
  preview_text TEXT,           -- extracted text for search and AI
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE item_link (
  id TEXT PRIMARY KEY,
  from_id TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
  to_id   TEXT NOT NULL REFERENCES work_item(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('blocks','relates_to')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, version INTEGER NOT NULL DEFAULT 1,
  UNIQUE (from_id, to_id, type)
);
-- 'blocks' chain = one-way linked list: enforce at most one active outgoing and one incoming 'blocks' per item
CREATE UNIQUE INDEX uq_blocks_out ON item_link(from_id) WHERE type='blocks' AND deleted_at IS NULL;
CREATE UNIQUE INDEX uq_blocks_in  ON item_link(to_id)   WHERE type='blocks' AND deleted_at IS NULL;

CREATE TABLE reminder (
  id TEXT PRIMARY KEY, work_item_id TEXT REFERENCES work_item(id) ON DELETE CASCADE,
  fire_at TEXT NOT NULL, kind TEXT NOT NULL,   -- task|end_of_day
  delivered_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
);

CREATE TABLE change_outbox (          -- feeds the future sync engine
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  entity TEXT NOT NULL, entity_id TEXT NOT NULL, op TEXT NOT NULL,  -- upsert|delete
  payload_json TEXT NOT NULL, created_at TEXT NOT NULL, synced_at TEXT
);

CREATE TABLE setting (key TEXT PRIMARY KEY, value_json TEXT NOT NULL);

CREATE VIRTUAL TABLE search_index USING fts5(
  item_id UNINDEXED, title, description, attachments, tokenize='unicode61 remove_diacritics 2'
);
```

Cycle detection for `blocks` links runs in the `LinkTasks` use case (walk the chain before insert); the unique indexes guarantee the linked-list shape.

**Repository ports (in TodayFlowCore)**

```swift
public protocol WorkItemRepository: Sendable {
    func item(id: WorkItem.ID) async throws -> WorkItem?
    func todayItems(on day: Date, calendar: WorkCalendar) async throws -> [WorkItem]
    func children(of parentId: WorkItem.ID) async throws -> [WorkItem]
    func save(_ item: WorkItem) async throws          // upsert, bumps version, writes outbox
    func softDelete(id: WorkItem.ID) async throws
    func move(id: WorkItem.ID, between before: WorkItem.ID?, and after: WorkItem.ID?) async throws
    func observeToday(on day: Date) -> AsyncStream<[WorkItem]>   // live updates for the UI
    func search(_ query: String) async throws -> [WorkItem]
}

public protocol LinkRepository: Sendable { /* add, remove, chain(for:), predecessors(of:) */ }
public protocol AttachmentRepository: Sendable { /* add, remove, list(for:) */ }
public protocol SyncEngine: Sendable { func pushPending() async throws; func pull() async throws }
```

**Cloud migration path**

1. **v1:** local only; outbox filled but not consumed (`NoopSyncEngine`).
2. **v2 (Apple devices):** `CloudKitSyncEngine` using the CloudKit private database via `CKSyncEngine`; each table maps to a record type; conflicts resolved last-writer-wins per field using `version` and `updatedAt`.
3. **v3 (optional server):** `RemoteSyncEngine` against Postgres (for example Supabase) over REST; the SQLite schema maps directly to Postgres tables. Swapping engines is a configuration change because the core only sees `SyncEngine`.

Files referenced by attachments are not uploaded by default; only metadata and links sync. Copied transient files (emails, images) sync as assets in v2.

## 7. Object recognition pipeline

Every drop runs through one pipeline that turns raw pasteboard data into a `CaptureDraft` (suggested title, attachments, metadata) in under 300 ms; slow work such as URL titles, text extraction and AI suggestions fills in afterwards.

1. **Receive.** `onDrop` / `NSDraggingDestination` collects all `NSItemProvider`s. Handle file URLs, file promises (`NSFilePromiseReceiver`, used by Outlook and Mail for messages and events), URLs, plain/rich text, and image data.
2. **Materialize.** Copy transient items (file promises, image data, `.eml`/`.msg`/`.ics`) into the app's `Attachments/` container; for persistent files and folders store a security-scoped bookmark instead of a copy.
3. **Classify.** Ordered list of `ObjectRecognizer`s; the first whose `canHandle` returns true wins. Each returns `RecognizedObject { type, uti, displayName, sourceApp, metadata, suggestedTitle, previewText }`.
4. **Draft.** Combine recognized objects into a `CaptureDraft` with default dates from `WorkCalendar` and priority P3. Open the quick-add sheet immediately.
5. **Enrich (async).** Fetch URL titles and favicons, extract PDF/Office text (PDFKit, `NSAttributedString` document reading), generate thumbnails (QuickLookThumbnailing), and, if AI is on, request a better title and summary. Update the sheet live unless the user already edited that field.

**Recognizers (v1, in priority order)**

| Recognizer | Detects | Suggested title | Metadata kept |
| --- | --- | --- | --- |
| OutlookEmail | `.eml`/`.msg` from Outlook, `ms-outlook://` links | Subject | From, to, received date, message-id |
| MailEmail | `message://` URLs, `.eml` from Apple Mail | Subject | From, date, message-id |
| CalendarEvent | `.ics`, Outlook event promises | Event title | Start, end, location, organizer, join link |
| TeamsMessage | `msteams:` / `teams.microsoft.com` links, text copied from Teams | First line of message, or "Teams: channel/chat" | Link, sender if present |
| Folder | directory file URL | Folder name | Path |
| OfficeDocument | Word, Excel, PowerPoint UTIs | File name | Size, page/sheet count |
| PDF | `com.adobe.pdf` | PDF title metadata or file name | Page count |
| Image | `public.image`, screenshots | File name, or AI caption | Dimensions |
| WebURL | http/https | Page title (async), else domain | Favicon |
| GenericFile | any other file URL | File name | UTI, size |
| PlainText | text | First line, ≤ 80 chars | Full text in description |

**Rules**

- Recognizers are pure and unit-tested with fixture files; adding a new type means adding one recognizer, nothing else.
- Icon type comes from the recognized type, never from the file extension alone (UTType conformance).
- Exact pasteboard types from Outlook and Teams vary by app version (classic vs new Outlook for Mac, Teams 2.x). Phase 0 includes a pasteboard-inspector spike to record real types before the recognizers are finalized.
- Clicking an attachment reopens the original: file → default app; email → `ms-outlook://` or `message://` deep link when available, else the saved `.eml`; Teams → its link.

## 8. LLM integration

AI is optional and off by default; when on, the app talks to any server that implements the OpenAI Chat Completions API (`POST {baseURL}/chat/completions`), so one client covers Ollama, LM Studio, llama.cpp server, vLLM, OpenAI, Azure OpenAI, OpenRouter and any other compatible gateway.

**Configuration (Settings → AI)**

| Setting | Example | Notes |
| --- | --- | --- |
| Provider preset | Ollama, LM Studio, OpenAI, Custom | Preset fills base URL |
| Base URL | `http://localhost:11434/v1` | Any OpenAI-compatible endpoint |
| API key | stored in Keychain | Optional for local servers |
| Model | `llama3.1:8b`, `gpt-4o-mini` | Free text + "Fetch models" via `GET /models` |
| Features | toggles per feature below |  |
| Privacy | "Send attachment text" on/off | Off sends only titles and metadata |
| Timeout | 20 s | AI never blocks capture |

**Port and client**

```swift
public protocol AIAssistant: Sendable {
    func suggestTask(from objects: [RecognizedObject]) async throws -> TaskSuggestion   // title, summary, priority, actions
    func breakDown(_ item: WorkItem) async throws -> [SubtaskSuggestion]
    func planDay(_ items: [WorkItem], hours: WorkCalendar) async throws -> DayPlan     // suggested order + reasons
    func ask(_ question: String, context: [WorkItem]) async throws -> AsyncThrowingStream<String, Error>
}

// TodayFlowAI: OpenAICompatibleAssistant implements AIAssistant
// - URLSession, async/await, streaming via Server-Sent Events (stream: true)
// - response_format: { type: "json_schema" } when supported; falls back to JSON-in-text parsing + validation
// - retries with exponential backoff (max 2), cancellation on sheet close
// - prompt templates are versioned files in the package, not string literals in views
```

**AI features (v1.x)**

- **Smart title and summary** for dropped objects (enrichment step 5).
- **Break down** a task into actions or subtasks, user picks which to keep.
- **Plan my day**: proposes an order based on priority, due times, dependencies and estimated effort; user accepts or drags.
- **Ask**: "What's left for the Q3 project?" answered from local data only.

**Guardrails**

- Every AI output is a suggestion shown for approval; nothing is created or changed silently.
- Requests include only the fields needed; the payload is visible in a "What was sent" disclosure.
- Local-model preset is the recommended default for sensitive work data.
- Graceful degradation: if the endpoint is unreachable, features hide their AI buttons and capture works normally.

A later option is an MCP server (Model Context Protocol) exposing the task store as tools, so external assistants can read and create tasks.

## 9. Non-functional requirements and engineering standards

The app must feel instant: measurable budgets below are release gates, not goals.

| ID | Requirement | Target |
| --- | --- | --- |
| NFR-01 | Drop → quick-add sheet visible | ≤ 300 ms (p95) |
| NFR-02 | Save task → visible in list | ≤ 50 ms |
| NFR-03 | Today query with 10,000 items in DB | ≤ 10 ms |
| NFR-04 | Full-text search over 10,000 items | ≤ 50 ms |
| NFR-05 | Cold launch to usable panel | ≤ 1 s on Apple silicon |
| NFR-06 | Idle memory / CPU | ≤ 80 MB, \~0% CPU |
| NFR-07 | Animations | 60 fps (120 on ProMotion), respect Reduce Motion |
| NFR-08 | Accessibility | Full keyboard use, VoiceOver labels, Dynamic Type where supported, WCAG AA contrast |
| NFR-09 | Data safety | Transactions on every write, daily automatic backup (keep 7), export to JSON/CSV |
| NFR-10 | Privacy | All data local by default; no telemetry without opt-in; API keys in Keychain |
| NFR-11 | Security | App Sandbox + Hardened Runtime, notarized, security-scoped bookmarks for files |
| NFR-12 | Localization | All strings in String Catalogs; English first, locale-aware dates and business hours |

**Engineering standards**

- Swift 6 language mode, strict concurrency checking on, no warnings in CI.
- SwiftLint + swift-format, enforced in CI and a pre-commit hook.
- SOLID and dependency inversion: features depend on protocols; no singletons except the composition root.
- Value types for entities; use cases are small structs with one `execute` method.
- Errors are typed (`enum CaptureError: Error`), surfaced to the user in plain language, logged with `os.Logger`.
- Database changes only through versioned GRDB migrations; never edit a shipped migration.
- Feature flags for unfinished features (AI, sync).
- Conventional Commits, trunk-based development, PRs reviewed, small and green.
- Documentation: DocC for public APIs of each package; ADRs (architecture decision records) in `/docs/adr`.

**Testing strategy**

| Layer | Tooling | Coverage target |
| --- | --- | --- |
| Core use cases and rules (dates, ordering, chains, roll-ups) | Swift Testing | ≥ 90% |
| Persistence (migrations, queries, outbox) | Swift Testing on in-memory and temp-file SQLite | ≥ 80% |
| Recognizers | Fixture files (.eml, .msg, .ics, PDFs, Office, URLs) | every recognizer |
| AI client | Mock HTTP server with recorded OpenAI-format responses | all features + failure modes |
| UI | XCUITest for capture, complete, reorder, link, end-of-day | critical flows |
| Performance | XCTest `measure` with 10k-item seed | NFR-01 to 05 |

CI: GitHub Actions on macOS runners runs build, lint, tests and performance checks on every PR; tagged builds are signed, notarized and published as DMG (Sparkle for updates) or via the Mac App Store.

## 10. Project plan

Plan for a usable MVP (drop, quick add, today list) at week 9 and v1.0 at about week 22, assuming one experienced Swift developer working with an AI coding assistant; a second developer shortens phases 2–3 by roughly a third.

&#91;embedded content: roadmap · 5 phases, 3 release gates\]

The MVP gate at week 9 is the key checkpoint: the app should already replace sticky notes for daily use before any hierarchy or AI work starts.

**Work breakdown**

1. **Phase 0–1 Foundations (weeks 1–5)**
   - Workspace, local packages, CI, SwiftLint, swift-format, ADR template.
   - Pasteboard-inspector spike: record drag types from classic and new Outlook, Teams, Mail, Finder, Safari, Chrome.
   - `TodayFlowCore`: entities, `WorkCalendar` (end-of-business rules), fractional ordering, chain rules, use cases with tests.
   - `TodayFlowPersistence`: migrations v1, repositories, FTS index, outbox, 10k-item seed for performance tests.
2. **Phase 2 MVP capture (weeks 6–9)**
   - Floating `NSPanel` with drop zone; quick-add sheet; recognizers for files, PDF, Office, images, URLs, text, emails, calendar events.
   - Today list with priority dots, attachment icons, sorting, drag reorder, complete with undo, progress ring.
   - Exit: Alpha (NFR-01 and NFR-02 met, used daily for one week).
3. **Phase 3 Complete v1 (weeks 10–16)**
   - Detail window with Markdown editor, actions, subtasks, attachments grid, links panel.
   - Hierarchy view (epics → projects → tasks) with drag to re-parent; progress roll-up.
   - Task chains: drop-on-task popover, connectors, locks, unlock animation.
   - Menu bar item, slim bar mode, notifications with actions, end-of-day review, celebration animations.
   - Exit: Beta (all FR-xx implemented, UI tests green).
4. **Phase 4 AI and release (weeks 17–22)**
   - AI settings, OpenAI-compatible client, smart titles, break down, plan my day.
   - Performance, accessibility and localization pass; backup and export.
   - Signing, notarization, Sparkle updates or App Store submission.
   - Exit: v1.0 (all NFR targets met).
5. **v2 (after v1.0)**: iOS/iPadOS app on the same packages, watchOS complication and today list, widgets, CloudKit sync, optional Postgres backend.

**Risks**

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Outlook/Teams drag data is inconsistent across versions | Titles and deep links missing | Phase 0 spike; fall back to generic file/text recognizers; user can always edit title |
| Sandbox limits access to dropped files later | Attachments fail to open | Security-scoped bookmarks; copy transient items into container |
| Floating panel feels intrusive | Users quit the app | Slim bar mode, auto-hide, user-chosen screen edge |
| Notification fatigue | Nudges ignored or disabled | Max 2 default nudges per day, Focus-aware, configurable |
| AI endpoints vary in OpenAI compatibility | Features break on some servers | Capability probe on connect; JSON fallback parsing; integration tests against Ollama and OpenAI |
| Sync conflicts in v2 | Data loss | Versioned records, tombstones, field-level merge, conflict log |

## 11. Instructions for AI coding agents

An AI agent building this app should work in small, test-first increments in the build order below, and treat the FR, NFR and schema sections of this document as the contract.

**Working rules**

- Read sections 2, 5 and 6 before writing code; never violate the layer rules in section 5.
- One increment = one package or feature slice + its tests + a passing CI run. Do not start the next increment with failing tests.
- Write the protocol (port) first, an in-memory implementation second, the real adapter third.
- Reference requirement IDs in commit messages and test names (`test_FR02_quickAddPrefillsEndOfBusiness`).
- Ask before adding any third-party dependency beyond GRDB, Sparkle and swift-format/SwiftLint.
- Never call network or AI services from `TodayFlowCore` or from views.

**Build order**

1. `TodayFlowCore`: `WorkItem`, `Attachment`, `ItemLink`, `ActionItem`, `Priority`, `Status`, `WorkCalendar`, `FractionalIndex`; use cases `CreateTask`, `CompleteTask`, `ReorderTask`, `LinkTasks`, `TodayQuery`, `RollUpProgress`.
2. `TodayFlowPersistence`: migration v1 (section 6 SQL), GRDB records, repositories, outbox writes, FTS triggers.
3. `TodayFlowRecognition`: `ObjectRecognizer` protocol and recognizers in section 7 order, with fixtures.
4. `TodayFlowDesign`: priority colors, icon mapping, progress ring, completion animations.
5. `TodayFlowFeatures`: Today list → Capture sheet → Task detail → Hierarchy → Settings.
6. `TodayFlowMac`: composition root (`AppEnvironment`), `NSPanel`, `NSStatusItem`, global hotkey, notifications.
7. `TodayFlowAI`: `OpenAICompatibleAssistant`, settings, the four features in section 8.
8. `TodayFlowSync`: `NoopSyncEngine` in v1; `CloudKitSyncEngine` in v2.

**Key acceptance criteria (Given / When / Then)**

- **Drop a PDF at 10:42 on a weekday.** Then the sheet opens in ≤ 300 ms, title = file name without extension, start = 10:42 today, end = 17:00 today, priority P3, one attachment with the PDF icon.
- **Drop an email at 18:30 (after business hours).** Then end defaults to 17:00 on the next business day.
- **Drop three files with ⌥ held.** Then three tasks are created, one attachment each.
- **Drag task A onto task B and choose "Before".** Then B shows a lock, a connector joins A and B, and completing A unlocks B.
- **Link B → A when A → B exists.** Then the link is rejected with "This would create a loop".
- **Delete B from chain A → B → C.** Then after confirmation the chain becomes A → C.
- **Drag a row from position 4 to 1.** Then display order persists across relaunch and the sort switches to Display order.
- **Two tasks remain at 15:00 (2 h before end).** Then one notification fires with Mark done / Snooze / Move to tomorrow.
- **Complete the last task of the day.** Then the ring reaches 100%, the "Day cleared" state shows with a celebration (static if Reduce Motion is on).
- **AI endpoint unreachable.** Then capture still works and AI buttons are hidden, with a status note in Settings.

**Open questions**

- Distribution: Mac App Store, direct download with Sparkle, or both?
- Should Epics and Projects have dates and priorities too, or only Tasks and Subtasks?
- Do dropped files stay as links to the original location (default above) or always get copied into the app?

## 12. Reference apps and feature ideas

The strongest ideas to borrow are a short daily planning ritual with a capacity check (Sunsama, Microsoft To Do), keyboard-first speed with a command palette (Linear, Akiflow), quick capture that grabs context from the frontmost app (Things), and opt-in motivation such as daily goals and streaks (Todoist). The biggest trap to avoid is monday.com-style feature sprawl.

**What each reference app does best**

| App | Known for | Borrow for TodayFlow | Avoid |
| --- | --- | --- | --- |
| [monday.com](https://support.monday.com/hc/en-us/articles/360019300579) | "My Work": one consolidated list of everything assigned to you, viewable by date, status, priority or board, plus a calendar toggle | Group-by options on the Today list (date, priority, status, project); user-chosen row fields, as monday lets users pick which fields show on Kanban cards ([G2 review](https://learn.g2.com/monday-review)) | Complexity: on [G2](https://www.g2.com/products/monday-com/reviews), complexity and overwhelming features are among the most-cited complaints |
| [Sunsama](https://sunsama.com/features/daily-planning-and-shutdown) | Guided morning planning and evening shutdown ritual | Morning sheet: review yesterday's carryover, estimate time per task, warn when the day is over-committed ([review](https://dupple.com/tools/sunsama-276fa)) | Heavy manual ritual; some users find it time-consuming. Keep ours under 60 seconds and skippable |
| [Akiflow](https://work-management.org/tasks/akiflow-review/) | Universal inbox that collects tasks from many tools; keyboard command bar | An Inbox lane for captured-but-unplanned items; global command bar; plan the day by keyboard alone | Inbox only shows items you flagged, with no AI triage ([analysis](https://get-alfred.ai/blog/is-akiflow-worth-it)) |
| [Things 3](https://apps.apple.com/ca/app/things-3/id904280696?mt=12) | Calm native Mac design; Quick Entry from anywhere; Quick Entry with Autofill grabs the current link or email | Autofill on the global hotkey (grab the frontmost Outlook message, browser tab or Finder selection); Markdown notes; repeating tasks; widgets and Control Center controls | Its fixed hierarchy (Areas/Projects/To-dos) has no task dependencies, which we add |
| [Todoist](https://todoist.com/help/articles/206209959-Tracking-productivity-with-Karma) | Karma points, daily/weekly goals and streaks, with days off and vacation mode | Optional daily goal and streak, weekend days off, vacation mode; a productivity view of tasks done per day | Points that drop as you fall behind; ours never penalize |
| [TickTick](https://appleinsider.com/articles/23/01/10/ticktick-6420-review-prioritized-to-do-list-with-focus-timer) | Eisenhower matrix, Pomodoro timer, a "constant reminder" option, and extra tools you switch on in settings | Matrix view (priority × due); focus timer on the current task; per-task "remind until done"; advanced tools off by default | Feature sprawl visible all at once |
| [Linear](https://www.925studios.co/blog/linear-design-breakdown-saas-ui-2026) | Speed as a design principle: optimistic UI, ⌘K command menu, single-key shortcuts | ⌘K for every action, `N` new task, `Space` complete, `P` priority, `T` move to tomorrow; never show a spinner for local actions | Shortcut-only discoverability; always pair with visible buttons |
| [Microsoft To Do](https://support.microsoft.com/en-US/ToDo/plan-and-connect-with-microsoft-to-do) | "My Day" with suggestions; flagged Outlook emails become tasks with an Open in Outlook link | Suggestions panel in the morning sheet (overdue, carryover, due soon); later, import flagged Outlook emails via Microsoft Graph | My Day empties every night; we carry unfinished work forward explicitly |
| [Structured](https://apps.apple.com/PH/app/id1499198946) | Visual timeline that puts tasks and calendar events on one line through the day | A timeline view of today (tasks with estimates placed between calendar events) | Minute-by-minute planning as the default; keep it an optional view |

**Features to add to the spec**

New requirement IDs continue from section 3. "v1" items should be added to the MVP or Complete v1 phase; the rest go to v1.x or v2.

| ID | Feature | Inspired by | Release |
| --- | --- | --- | --- |
| FR-50 | **Recurring tasks** (daily, weekdays, weekly, monthly, custom); a gap in the current spec | Things, Todoist | v1 |
| FR-51 | **Morning plan sheet** on first open of the day: carryover, overdue, suggestions, one-click add to today; skippable, under 60 s | Sunsama, Microsoft To Do | v1 |
| FR-52 | **Time estimate** per task (15 m steps) and a **capacity bar** in the header: planned hours vs hours left until end of business, turns amber when over | Sunsama | v1 |
| FR-53 | **Command palette (⌘K)** for every action, plus single-key shortcuts and a `?` cheat sheet | Linear, Akiflow | v1 |
| FR-54 | **Inbox lane** for captured items with no date; drag to Today or set a date | Akiflow, Things, Structured | v1 |
| FR-55 | **Group by** date, priority, status or project on the Today list, in addition to the three sorts | monday.com My Work | v1 |
| FR-56 | **Shutdown summary** added to the end-of-day review: tasks done, time estimated vs available, what moved to tomorrow | Sunsama | v1 |
| FR-57 | **Autofill quick entry**: the global hotkey grabs the frontmost Outlook message, browser tab, or Finder selection as an attachment | Things | v1.x |
| FR-58 | **Daily goal and streak** (default: clear the day), with days off and vacation mode; off by default; never subtracts | Todoist | v1.x |
| FR-59 | **Productivity view**: tasks done per day and week, by project color | Todoist | v1.x |
| FR-60 | **Focus timer** on the current task, shown in the slim bar and menu bar | TickTick, Sunsama | v1.x |
| FR-61 | **Remind until done** option per task (repeat nudge every N minutes) | TickTick | v1.x |
| FR-62 | **Eisenhower matrix view** mapping priority (importance) × due soon (urgency) | TickTick | v1.x |
| FR-63 | **Task templates** (title, actions, subtasks, default priority) | Linear | v1.x |
| FR-64 | **Customizable row fields** (choose which of icons, time, project, estimate appear) | monday.com | v1.x |
| FR-65 | **Flagged Outlook email import** via Microsoft Graph as suggestions | Microsoft To Do | v2 |
| FR-66 | **Timeline view** of today with calendar events from EventKit | Structured, Sunsama | v2 |
| FR-67 | **Kanban view** by status | monday.com, TickTick | v2 |
| FR-68 | **Widgets and Control Center controls** (progress ring, next task, new task) on Mac, iPhone and Watch | Things | v2 |

**UI principles confirmed by the references**

- One calm default screen (Things, Structured); power tools live behind toggles (TickTick) and ⌘K (Linear).
- Every local action is instant and optimistic; no spinners for anything that touches only the local database (Linear).
- Planning is a short ritual with a realistic capacity check, not an endless list (Sunsama).
- Motivation is opt-in and forgiving: goals, streaks and celebrations, never penalties (Todoist, with our no-guilt rule).
- Capture comes from where the work already is: drag and drop, the hotkey with autofill, and later flagged emails (Things, Akiflow, Microsoft To Do).

Data model impact: add `estimate_minutes INTEGER`, `recurrence_rule TEXT` (RFC 5545 RRULE) and `is_inbox` (or a null `start_at`) to `work_item`, and a `daily_stat` table for streaks and the productivity view.
