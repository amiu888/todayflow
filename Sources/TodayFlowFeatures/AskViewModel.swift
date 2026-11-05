import Foundation
import Observation
import TodayFlowCore

/// "Ask" (driver.md §8): answers questions from the local task context only,
/// streaming tokens as the model produces them.
@MainActor
@Observable
public final class AskViewModel {
    public var question: String = ""
    public private(set) var answer: String = ""
    public private(set) var isAsking = false
    public private(set) var lastError: String?

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private let assistant: any AIAssistant
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored public var onFinished: (@MainActor () -> Void)?

    public init(
        repository: any WorkItemRepository,
        calendar: WorkCalendar = .standard,
        assistant: any AIAssistant,
        clock: @escaping @Sendable () -> Date = { .now },
        onFinished: (@MainActor () -> Void)? = nil
    ) {
        self.repository = repository
        self.calendar = calendar
        self.assistant = assistant
        self.clock = clock
        self.onFinished = onFinished
    }

    /// Streams an answer to the current question. A second call cancels the
    /// first request (the sheet's Cancel button cancels too).
    public func ask() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        task?.cancel()
        answer = ""
        lastError = nil
        isAsking = true

        let repository = self.repository
        let assistant = self.assistant

        task = Task { @MainActor [weak self] in
            // Ask spans the whole local store, not just today: questions like
            // "What's left for the Q3 project?" need older open items too.
            let context = await repository.allItems()
                .filter { !$0.status.isTerminal }

            do {
                let stream = try await assistant.ask(text, context: context)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    self?.answer += chunk
                }
            } catch is CancellationError {
                // The user closed the sheet or asked again.
            } catch {
                self?.lastError = error.localizedDescription
            }
            self?.isAsking = false
        }
    }

    /// Cancels any in-flight request and closes the sheet.
    public func cancel() {
        task?.cancel()
        task = nil
        isAsking = false
        onFinished?()
    }
}
