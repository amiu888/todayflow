import Foundation
import TodayFlowCore
import TodayFlowPersistence

/// The v1 synchronization engine (driver.md §6, §11 build order 8).
///
/// v1 is local-only: every write already lands in `change_outbox` in the same
/// transaction, but the no-op engine deliberately neither pushes nor consumes
/// those rows. Keeping the outbox intact means a v2 `CloudKitSyncEngine` can
/// replay everything that happened while the app ran offline.
///
/// The optional `OutboxStore` exists so the app/tests can prove that behavior;
/// it is never mutated here.
public struct NoopSyncEngine: SyncEngine, Sendable {
    private let outbox: OutboxStore?

    public init(outbox: OutboxStore? = nil) {
        self.outbox = outbox
    }

    /// No-op: leaves every pending outbox row for a future real engine.
    public func pushPending() async throws {
        _ = outbox
    }

    /// No-op: there is no server to pull from in v1.
    public func pull() async throws {}
}
