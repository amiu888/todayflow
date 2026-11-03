# ADR-0001: Single Swift package with layered targets

- **Status:** Accepted
- **Date:** 2026-11-02
- **Deciders:** build
- **Consulted:** driver.md §5 (architecture), §11 (engineering standards)
- **Informed:** —

## Context

`driver.md` §5 describes the codebase as "one Xcode workspace, local Swift packages"
with a directory layout of `Packages/TodayFlowCore/`, `Packages/TodayFlowPersistence/`,
etc. — i.e. each logical package as its own Swift package with its own `Package.swift`.
The binding contract in §5/§11 is the **layer rule**: `TodayFlowCore` imports only
Foundation; features depend on use cases, never repositories; every port has a
production and an in-memory adapter; platform code stays behind `#if os(macOS)`.

Two ways to honor that:

1. **Separate local packages** — literal reading of §5. Strong isolation, but each needs
   its own `Package.swift`, versioning, and a workspace to tie them together; iterating
   across a dependency boundary (core change → re-resolve) is slower, and command-line
   `swift test` across the graph is awkward.
2. **One Swift package, multiple targets** — the standard SwiftPM layout for a large
   app. Target `dependencies:` enforce the exact same layer rule, and the whole graph
   builds and tests from a single `swift build` / `swift test` at the root.

## Decision

We use a **single root Swift package** (`Package.swift`) with one library target per
logical package from `driver.md` §5 (`TodayFlowCore`, `TodayFlowPersistence`, …) and a
matching test target each, under `Sources/` and `Tests/`. The §5 layer rule is enforced
by declaring only the permitted target dependencies (e.g. `TodayFlowCore` has no
dependencies; `TodayFlowPersistence` depends only on `TodayFlowCore`).

The directory names in `driver.md` are preserved in spirit: the core lives in
`Sources/TodayFlowCore/`. We treat "package" and "target" as interchangeable in this
repo — the architectural contract (dependency direction, Foundation-only core) is what
matters, not the packaging mechanism.

## Consequences

- **Easier:** fast, single-command build/test across the whole graph; trivially
  enforces the layer rule at compile time; no workspace file to maintain; each target
  still compiles independently so a core change is cheap.
- **Harder / trade-off:** no independent versioning or publishing of individual packages
  (not needed for a v1 that ships as one app). If a package later needs to be published
  or consumed by a separate app, we can split it out into its own package without
  changing its internal code.
- **Forces:** new logical packages are added by appending a target to the root
  `Package.swift`, not by creating a new package directory.
