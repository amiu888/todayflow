# TodayFlow

Native macOS task app (SwiftUI + AppKit). The contract is `driver.md` (12 sections).
Increments 1–4 are complete and committed: Core, Persistence, Recognition, Design (242 tests green).
Increment 5 (Features) splits into 5a Today, 5b Capture, 5c Detail, 5d Hierarchy, 5e Settings.

## Context rules (keep sessions small)
- Never read or search inside: `.build/`, `DerivedData/`, `Pods/`, `*.sqlite`, `*.xcodeproj/project.pbxproj`.
- Read large files in line ranges, or grep for the symbol you need, instead of whole files.
- One focused task per session; commit per increment.
