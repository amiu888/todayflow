# TodayFlow — visual design

The design brief: a calm daily planning instrument for one person. It should feel
fast and quiet enough to open a hundred times a day, but rich enough that a glance
answers “what is left, what is next, and what is coming?”

## Direction

**Cinematic daylight.** A near-black indigo surface for focus, with one luminous
sky→royal→violet gesture behind the day header. The light theme is the same system
in white and slate. Lists, filters and controls stay quiet; urgency is the only
thing allowed to interrupt.

## Tokens

| Token | Dark | Light | Use |
| --- | --- | --- | --- |
| Background | `#07090F` | `#F7F9FF` | Window / panel base |
| Surface | `#151F2E` | `#FFFFFF` | Cards, filters, rows |
| Raised surface | `#1B2739` | `#F1F5F9` | Text fields, nested controls |
| Primary text | `#F1F5F9` | `#0F172A` | Titles, task names |
| Secondary text | `#94A3B8` | `#475569` | Dates, meta, captions |
| Accent | `#60A5FA` | `#2563EB` | Selection, primary actions |
| Accent strong | `#818CF8` | `#1D4ED8` | Gradient midpoint |
| Violet | `#A78BFA` | `#7C3AED` | Gradient end |
| Success | `#34D399` | `#059669` | Completed |
| Warning | `#FBBF24` | `#D97706` | Due soon |
| Danger | `#F87171` | `#DC2626` | Overdue / errors |
| Hairline | `#263449` | `#E2E8F0` | One-pixel structure |

The selected day/chip uses a **subtle accent tint + accent border**, not a bright
gradient. The full gradient is reserved for the week-strip selection and the
capture card rim.

## Type

SF Pro for content, SF Rounded for numerals and the date header. One display
weight, one body weight, one caption. Section labels are sentence case, never
all-caps. Dates are always locale-aware.

## Layout

```
┌──────────────────────────────────┐
│ Today          4 November  [↗]   │
│ M  T  W  T  F  S  S   ← week     │
│ ◯ 3 / 7 done · 4 left            │
│ All  Blocked  P1–P2   ▣ ⇅ ⌕     │
│ Due soon · 12 min                │
│ Overdue 1                        │
│ ○ 9:00  Write copy       9:30    │
│ Today 3                          │
│ ○ 10:30 Review contract  17:00   │
│ Done today ▸                     │
│ Tomorrow & upcoming      See all │
│ • Plan launch            Tomorrow│
└──────────────────────────────────┘
```

The week strip is the navigation model: tap a day to plan it in place. Future
rows carry a small “…” menu for priority, start time, move up/down, and open.
Working trays sit between the filters and the list: named drop areas for the
tasks currently in play. A separate Calendar window provides week and month
boards, and Focus mode turns one task into a large timer with pause/+5/Done.
A new capture is inserted at the **top** of today’s list so it is never hidden
below the fold.

## Motion

- **Due soon:** a clock symbol pulses and the row gets an amber tint; a banner
  appears above the list. Reduced Motion disables the pulse.
- **Completion:** the checkmark symbol transition and progress ring update.
- **Window docking:** after a drag, the floating panel eases to a screen edge or
  adjacent window.
- **Capture:** the sheet is a springy material card with a 1px gradient rim.

## Influences

- **Things 3** — calm list rhythm, Today/Upcoming separation, restraint.
- **Structured** — the week strip and visual day planning.
- **Sunsama** — planning ritual and a realistic, time-aware day.
- **Llama Life** — urgency made visible without noise.
- **Akiflow** — keyboard-first capture and a compact command surface.

## Skills used

- Anthropic `frontend-design` (official) for the aesthetic plan and critique.
- Anthropic `theme-factory` for the dark/light token system.
- Anthropic `test-driven-development`, `systematic-debugging`,
  `verification-before-completion` for the implementation and UI-test loop.
