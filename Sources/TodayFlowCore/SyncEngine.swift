import Foundation

/// Port for cross-device synchronization (driver.md §5, §6).
///
/// v1 ships a no-op engine (single device); the real engine lands in
/// TodayFlowSync. The port lives in Core so features can call it without
/// depending on the sync implementation.
public protocol SyncEngine: Sendable {
    /// Push all pending local changes (the `change_outbox`) to the server.
    func pushPending() async throws

    /// Pull remote changes and merge them into the local store.
    func pull() async throws
}
