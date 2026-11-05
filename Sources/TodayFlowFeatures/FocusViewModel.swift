import Foundation
import Observation
import TodayFlowCore
#if canImport(AppKit)
import AppKit
#endif

/// One focused work session on a task (Structured/Sunsama/Llama Life style).
///
/// A 25-minute timer by default, capped by the time left before the task is
/// due. The session never changes the task until the user presses Done.
@MainActor
@Observable
public final class FocusViewModel {
    public private(set) var item: WorkItem?
    public private(set) var remaining: TimeInterval = 25 * 60
    public private(set) var total: TimeInterval = 25 * 60
    public private(set) var isRunning = false
    public private(set) var isFinished = false
    public private(set) var lastError: String?

    @ObservationIgnored private let itemId: UUIDv7
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let linkRepository: any LinkRepository
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored public var onClosed: (@MainActor () -> Void)?

    public init(
        itemId: UUIDv7,
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        clock: @escaping @Sendable () -> Date = { .now },
        onClosed: (@MainActor () -> Void)? = nil
    ) {
        self.itemId = itemId
        self.repository = repository
        self.linkRepository = linkRepository
        self.clock = clock
        self.onClosed = onClosed
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return max(0, min(1, remaining / total))
    }

    public var isOverdue: Bool {
        guard let item else { return false }
        return item.endAt < clock()
    }

    public func load() async {
        item = await repository.item(itemId)
        guard let item else { return }

        let untilDue = item.endAt.timeIntervalSince(clock())
        let session = min(25 * 60, max(5 * 60, untilDue))
        total = session
        remaining = session
        isFinished = false
        start()
    }

    public func toggleTimer() {
        isRunning ? pause() : start()
    }

    public func start() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        isFinished = false
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                self.remaining = max(0, self.remaining - 1)
                if self.remaining <= 0 {
                    self.isRunning = false
                    self.isFinished = true
                    #if canImport(AppKit)
                    NSSound.beep()
                    #endif
                    return
                }
            }
        }
    }

    public func pause() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    public func extend(by seconds: TimeInterval = 5 * 60) {
        remaining += seconds
        total = max(total, remaining)
        isFinished = false
        start()
    }

    public func complete() async {
        pause()
        guard let item else { return }
        do {
            try await CompleteTask(
                repository: repository,
                linkRepository: linkRepository
            ).execute(item.id, at: clock())
            onClosed?()
        } catch CompleteTask.Error.blocked {
            lastError = "This task is blocked by an unfinished prerequisite."
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func close() {
        pause()
        onClosed?()
    }

    public var timeText: String {
        let seconds = Int(remaining.rounded())
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
