# TodayFlow for iPhone — design (v1)

Status: **proposal, not built**. Nothing here is implemented until approved.

## 1. Goal

The Mac app is the workbench: always on screen, tasks dragged in from Outlook,
Finder and Chrome, trays and windows. The iPhone app is the **companion**:

- see today at a glance and tick things off,
- capture a task in seconds (type it, or **Share → TodayFlow** from Mail, Safari, Photos),
- read a task's whole story (notes, people, attachments),
- get reminded on time.

Both apps share one database format and sync through the TodayFlow server, so a
task added on the phone appears on the Mac within seconds, and the Mac keeps
writing the Obsidian archive for both.

## 2. Shape of the code

One repo, one set of shared modules, two apps.

```
TodayFlow/
├─ Sources/
│  ├─ TodayFlowCore            shared  (rules, entities, use cases)
│  ├─ TodayFlowPersistence     shared  (GRDB database, same migrations)
│  ├─ TodayFlowSync            shared  (server sync client)
│  ├─ TodayFlowRecognition     shared  (turns shared text/URLs/files into tasks)
│  ├─ TodayFlowAI              shared  (AI gated by OS version at run time)
│  ├─ TodayFlowDesign          shared  (colors, priority palette, type)
│  ├─ TodayFlowFeatures        shared view models; Mac-only views fenced off
│  ├─ TodayFlowMac             Mac app shell (unchanged)
│  └─ TodayFlowPhone           NEW: iPhone screens
└─ iOS/
   ├─ project.yml              NEW: XcodeGen spec (no hand-edited .pbxproj in git)
   ├─ TodayFlowPhoneApp/       NEW: app entry, Info.plist, entitlements
   └─ ShareExtension/          NEW: "Share → TodayFlow"
```

Why an Xcode project for the phone: SwiftPM can build the Mac executable, but an
iOS app with a share extension, app group and signing needs an Xcode project.
`project.yml` + XcodeGen keeps it reviewable text; the generated project is not
committed.

### What has to change in the shared code first

Measured on 2026-11-25 by building each module for the iOS simulator:

| Module | Today | Change |
|---|---|---|
| Core | 1 error | `ActivityActor.current` reads the Mac user name → "local" on iOS (no account name there) |
| Persistence, Sync, Design | build after the Core fix | none |
| Recognition | 2 errors | security-scoped bookmarks are Mac-only → plain bookmarks on iOS |
| AI | 25 errors | Apple Intelligence needs iOS 26 → `@available` checks (or iOS 26 minimum, see §8) |
| Features | AppKit in 15 of 72 files | fence the Mac-only files with `#if os(macOS)`; the phone gets its own views |

**M1 done (2026-11-25):** all shared modules build for the iOS simulator. Mac-only
screens are fenced with `#if os(macOS)` (TodayView, DetailView, TaskRowView,
SettingsView, CaptureSheetView/Host, TaskHistoryView, TrayStripView,
TrayDetailView, TaskDragSource, PasteCatcher; window helpers become empty views
on iOS). Mac-only SwiftUI styles go through `PlatformModifiers.swift`
(`onEscape`, `linkButtonStyle`, `checkboxToggleStyle`, `borderlessMenuStyle`,
`radioGroupPickerStyle`, `PlatformClipboard`), which compile to the original
calls on macOS.

The Mac app must behave exactly as now; every change above is guarded so the
macOS build is byte-for-byte the same logic. The existing 966 tests stay green.

## 3. Screens (v1)

Three tabs plus sheets. Standard iOS navigation, large titles, swipe actions,
long-press menus. Dark and light follow the system; colors and priority pills
come from `TodayFlowDesign`, so it looks like TodayFlow.

### 3.1 Today (tab 1)

```
┌──────────────────────────────┐
│ Today                    ＋  │
│ Tue 24 Nov · 2/8 done · 5h 10│  progress + planned load
│ ┌──┬──┬──┬──┬──┬──┬──┐       │
│ │24│25│26│27│28│29│30│ week  │  tap a day to plan it
│ └──┴──┴──┴──┴──┴──┴──┘       │
│ (All)(Blocked)(P1–P2)(#tag ▾)│  filter chips
│                              │
│ OVERDUE · 2                  │
│ ○ P1 Vendor contract   Fri   │
│ ○ P3 Call supplier  09:00 📎 │
│ TODAY · 4                    │
│ ○ P2 Review Q4 roadmap 17:00 │
│   Launch Q4 · Maria          │  project · people
│ ○ P3 Budget draft      18:00 │
│ UPCOMING · 9            ▸    │  collapsed
│ DONE TODAY · 2          ▸    │
└──────────────────────────────┘
  [Today]   [Calendar]   [Search]
```

- **Swipe right:** complete (with Undo toast). **Swipe left:** Tomorrow · Priority · Delete.
- **Long press:** the same menu as the Mac's right-click (reschedule, priority, project, tags, delete).
- **Tap:** task detail. **＋:** quick add.
- Reuses `TodayViewModel` (sections, filters, week strip, undo) unchanged.
- Not in v1: trays (Mac workbench feature), manual drag reordering.

### 3.2 Task detail (pushed screen)

```
┌──────────────────────────────┐
│ ‹ Today                  ⋯   │  ⋯ = reschedule, tomorrow,
│ Review Q4 roadmap            │      reminder, repeat, project,
│ (P2 High)(To do)(Due Fri 17:00)│     delete, open in Obsidian
│ #launch #Q4                  │
│ ┌ Summary ─────────────────┐ │
│ │ Email from Maria about…  │ │
│ └──────────────────────────┘ │
│ NOTES                        │  newest first, time-stamped
│ 04 Nov 16:10                 │
│ Waiting on pricing from Maria│
│ PEOPLE   Maria Silva · Acme  │  tap → call / mail
│ RELATED  Blocked by Pricing… │
│ FILES    roadmap.pdf  📎     │  tap → Quick Look / share
│ HISTORY  ▸                   │  activity timeline
│┌────────────────────────────┐│
││ Add a note…            Send││  pinned to keyboard
│└────────────────────────────┘│
└──────────────────────────────┘
```

- Reuses `DetailViewModel` and `DescriptionLog` (the same time-stamped notes as the Mac and Obsidian).
- Title and pills edit in place; date pills open the system date picker.

### 3.3 Quick add (sheet)

```
┌──────────────────────────────┐
│ New task               Add   │
│ Call Maria tomorrow 3pm #Q4  │  natural language, live chips
│ (Tomorrow 15:00)(#Q4)        │  what was understood
│ Priority  P3 ▾   Project  –▾ │
└──────────────────────────────┘
```

Reuses `ParseNaturalLanguageDates`, `SmartTitle`, `TaskSchedule` (start at the
top of the hour, due after start) — the same rules as the Mac.

### 3.4 Calendar (tab 2)

Week strip with dots (as the Mac header) and the selected day's tasks below;
a Week / Month switch. Reuses `CalendarViewModel`.

### 3.5 Search (tab 3)

Quick Find as a screen: search field on top, filter tokens `#tag @person
/project due:today overdue done`, recent tasks when empty. Reuses
`QuickFindModel` and `TaskSearch`.

### 3.6 Settings (from Today's ⋯ menu)

- **Sync:** server address + pairing code (same flow as Mac Settings ▸ Sync), status, Sync now.
- **Notifications:** reminders on/off, due-soon nudges (12 h / 5 h / 1 h).
- **Work hours:** shared `WorkCalendar` settings.
- About, tutorial link.

## 4. Share → TodayFlow (share extension)

The phone's replacement for drag-and-drop.

```
 Mail / Safari / Photos / Files
            │  Share → TodayFlow
            ▼
┌──────────────────────────────┐
│ Add to TodayFlow       Add   │
│ Re: Q4 pricing               │  title from the shared item
│ (Today 17:00)  P3 ▾          │
│ 🔗 mail / page / photo        │  what will be attached
└──────────────────────────────┘
```

- Accepts text, URLs (web pages, Jira links), images, PDFs and files.
- The extension does **not** open the database (extensions have tight memory
  limits and two processes writing one SQLite file is a risk). It writes a small
  JSON "inbox" item plus any file into the shared **app group** folder.
- The app imports the inbox when it opens or comes to the foreground, through
  the existing `RecognitionPipeline` + `Materializer` — the same code that turns
  Mac drops into tasks (Jira keys, page titles, email subjects).

## 5. Sync and data

- The phone has its own local database (same GRDB schema and migrations as the Mac).
- It pairs with the TodayFlow server like a Mac does; `SyncRunner` runs on
  launch, on foreground, every 10 s while open, and on "Sync now".
- Without a server, the phone works on its own.
- **Away from home** the phone can only reach the server over Tailscale (the
  server is home-network only today; the NAS's Tailscale app is stopped). In the
  home network, `http://<nas>.local:8787` needs iOS's Local Network permission and
  an App Transport Security exception for local addresses.
- Obsidian: the phone does **not** talk to Obsidian. Its tasks reach the server,
  the Mac pulls them, and the Mac's archive writes them to the vault.

## 6. Notifications

- Per-task reminders → local notifications (`UserNotifications`, same API as macOS).
- Due-soon nudges (12 h / 5 h / 1 h) → notifications, reusing `DueNudgePlanner`.
- Notification actions: **Complete**, **Tomorrow**, **Open**.

## 7. Not in v1 (later)

Trays, Focus mode, Insights, Daily Report, AI writer/summaries, contacts
management and import (contacts are shown read-only), Obsidian settings,
home-screen widgets and Control Center controls (v1.1), Apple Watch, iPad layout.

## 8. Decisions needed

| # | Question | Recommendation |
|---|---|---|
| 1 | Minimum iOS | **iOS 26**: no AI availability branches; covers iPhone 11 and later. (iOS 17 is possible but adds checks.) |
| 2 | iPhone only, or iPad too | **iPhone only** for v1; SwiftUI makes an iPad layout a later step |
| 3 | Sync away from home | **Turn on Tailscale** on the NAS and the phone before testing outside the house |
| 4 | Install | **TestFlight** (your developer account), plus direct Xcode installs while building |
| 5 | Bundle id / name | `com.todayflow.ios`, display name "TodayFlow" (separate from the Mac's `com.todayflow.app`) |

## 9. Build order

Each milestone ends with a build on the simulator, tests, and a commit. The Mac
app and its tests must stay unchanged and green at every step.

| # | Milestone | Who | Done when |
|---|---|---|---|
| M1 | Shared code builds for iOS (§2 fixes, `#if os(macOS)` fences) | Claude | all shared modules build for iOS; 966 Mac tests pass |
| M2 | Xcode project (XcodeGen), empty app with tabs, app group, signing | Claude | app launches in the simulator |
| M3 | Today tab + task row + swipe/long-press | Kapitsa from spec, Claude reviews | matches §3.1 with seeded data |
| M4 | Task detail + notes + quick add | Kapitsa from spec, Claude reviews | §3.2–3.3 work against the real database |
| M5 | Calendar + Search tabs | Kapitsa from spec, Claude reviews | §3.4–3.5 |
| M6 | Sync pairing + settings | Claude | phone and Mac exchange tasks through the server |
| M7 | Share extension + inbox import | Claude | sharing a Safari page and a photo creates tasks |
| M8 | Notifications | Claude | reminder and nudges fire; actions work |
| M9 | TestFlight build | Claude | installed on your iPhone |

Rough size: 10–25 M tokens processed with Claude alone; about 6–14 M with
Kapitsa writing the M3–M5 screens. One milestone per session keeps it at the
low end.
