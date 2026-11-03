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

/// A single-device sync engine that records nothing (driver.md §5: "Noop in v1").
///
/// Lets the app run and be tested without a server; the TodayFlowSync package
/// provides the real implementation behind this same port.
public struct NoopSyncEngine: SyncEngine, Sendable {
    public init() {}

    public func pushPending() async throws {}
    public func pull() async throws {}
}
