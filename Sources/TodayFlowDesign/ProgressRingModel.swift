import Foundation
import TodayFlowCore

/// The model behind the header progress ring (driver.md §4 wireframe: "◔ 5 / 9
/// done     4 left"). Holds the fraction the ring draws and the labels the
/// header prints, so the view stays a dumb renderer.
public struct ProgressRingModel: Sendable, Equatable {
    public let done: Int
    public let total: Int
    public let fraction: Double

    public init(done: Int, total: Int) {
        let total = max(0, total)
        let done = min(max(0, done), total)
        self.done = done
        self.total = total
        self.fraction = total == 0 ? 0 : min(1, Double(done) / Double(total))
    }

    /// Builds from a roll-up (driver.md §2). The fraction is the roll-up's own
    /// — clamped to 0…1 — so a weighted roll-up drives the ring exactly as the
    /// repository computed it.
    public init(result: RollUpProgress.Result) {
        let total = max(0, result.total)
        let done = min(max(0, result.done), total)
        self.done = done
        self.total = total
        self.fraction = total == 0 ? 0 : min(1, max(0, result.fraction))
    }

    public var isComplete: Bool { total > 0 && done == total }

    public var remaining: Int { max(0, total - done) }

    public var doneLabel: String { "\(done) / \(total) done" }

    public var remainingLabel: String { "\(remaining) left" }
}
