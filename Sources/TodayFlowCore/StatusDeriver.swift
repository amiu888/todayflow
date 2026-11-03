import Foundation

/// Derives the presentation status of a work item from its stored status and its
/// blocking prerequisites (driver.md §2: "Blocked is derived from links").
///
/// `blocked` is a *derived* state, never persisted (the schema stores only
/// `todo|in_progress|done|cancelled`). An item whose stored status is non-terminal
/// and that has at least one prerequisite not yet done is surfaced as `.blocked`.
public struct StatusDeriver: Sendable {
    public init() {}

    /// - Parameters:
    ///   - stored: the item's persisted status (`todo` / `inProgress` / `done` / `cancelled`).
    ///   - blockers: the item's direct prerequisites (the `from` end of `.blocks` links
    ///     pointing at the item).
    /// - Returns: `.blocked` if non-terminal with an unresolved prerequisite, else `stored`.
    public func derive(stored: Status, blockers: [WorkItem]) -> Status {
        guard !stored.isTerminal else { return stored }
        return blockers.contains { !$0.status.isComplete } ? .blocked : stored
    }
}
