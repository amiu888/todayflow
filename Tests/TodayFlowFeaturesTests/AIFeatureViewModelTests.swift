import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

// MARK: - Deterministic clock

private let aiTestCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Wednesday 2026-11-04, 10:00 UTC.
private let aiTestNow = aiTestCalendar.date(
    from: DateComponents(year: 2026, month: 11, day: 4, hour: 10)
)!

private let aiTestWork = WorkCalendar(
    startHour: 9,
    endHour: 17,
    workWeekdays: [2, 3, 4, 5, 6],
    calendar: aiTestCalendar
)

private func aiDate(_ hour: Int) -> Date {
    aiTestCalendar.date(
        from: DateComponents(year: 2026, month: 11, day: 4, hour: hour)
    )!
}

// MARK: - Stubs

private struct StubFailure: Error, LocalizedError, Sendable {
    var errorDescription: String? { "stub failure" }
}

private struct StubAssistant: AIAssistant {
    var suggestion = TaskSuggestion(title: "AI title")
    var subtasks: [SubtaskSuggestion] = []
    var plan = DayPlan()
    var answerChunks: [String] = []
    var failure: StubFailure?

    func suggestTask(from objects: [RecognizedObject]) async throws -> TaskSuggestion {
        if let failure { throw failure }
        return suggestion
    }

    func breakDown(_ item: WorkItem) async throws -> [SubtaskSuggestion] {
        if let failure { throw failure }
        return subtasks
    }

    func planDay(_ items: [WorkItem], hours: WorkCalendar) async throws -> DayPlan {
        if let failure { throw failure }
        return plan
    }

    func ask(
        _ question: String,
        context: [WorkItem]
    ) async throws -> AsyncThrowingStream<String, Error> {
        if let failure { throw failure }
        let chunks = answerChunks
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish()
        }
    }
}

private struct StubCatalog: AIModelCatalog {
    var models: [String] = []
    var failure: StubFailure?
    func listModels() async throws -> [String] {
        if let failure { throw failure }
        return models
    }
}

@MainActor
private final class CompletionLog {
    private(set) var count = 0
    func record() { count += 1 }
}

private func aiTask(_ title: String, order: String) -> WorkItem {
    WorkItem(
        title: title,
        startAt: aiDate(9),
        endAt: aiDate(17),
        displayOrder: order
    )
}

// MARK: - Plan my day

struct DayPlanViewModelTests {
    @Test @MainActor
    func load_showsProposedOrderWithReasons() async {
        let repository = InMemoryWorkItemRepository()
        let first = aiTask("First", order: "a1")
        let second = aiTask("Second", order: "a2")
        let third = aiTask("Third", order: "a3")
        for task in [first, second, third] { await repository.seed(task) }

        let plan = DayPlan(
            summary: "Hard first.",
            order: [
                .init(itemId: third.id, reason: "Longest"),
                .init(itemId: first.id, reason: "Quick win"),
                .init(itemId: second.id, reason: "Later"),
            ]
        )
        let model = DayPlanViewModel(
            repository: repository,
            calendar: aiTestWork,
            assistant: StubAssistant(plan: plan),
            clock: { aiTestNow }
        )

        await model.loadAndPlan()

        #expect(model.summary == "Hard first.")
        #expect(model.rows.map(\.title) == ["Third", "First", "Second"])
        #expect(model.rows.first?.reason == "Longest")
        #expect(model.lastError == nil)
    }

    @Test @MainActor
    func apply_writesTheProposedOrderAndCloses() async throws {
        let repository = InMemoryWorkItemRepository()
        let first = aiTask("First", order: "a1")
        let second = aiTask("Second", order: "a2")
        let third = aiTask("Third", order: "a3")
        for task in [first, second, third] { await repository.seed(task) }

        let log = CompletionLog()
        let model = DayPlanViewModel(
            repository: repository,
            calendar: aiTestWork,
            assistant: StubAssistant(
                plan: DayPlan(order: [
                    .init(itemId: third.id),
                    .init(itemId: first.id),
                    .init(itemId: second.id),
                ])
            ),
            clock: { aiTestNow },
            onFinished: { [log] in log.record() }
        )

        await model.loadAndPlan()
        await model.apply()

        let ordered = await repository.allItems().map(\.title)
        #expect(ordered == ["Third", "First", "Second"])
        #expect(log.count == 1)
    }

    @Test @MainActor
    func load_emptyDayShowsFriendlyError() async {
        let model = DayPlanViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: aiTestWork,
            assistant: StubAssistant(),
            clock: { aiTestNow }
        )

        await model.loadAndPlan()

        #expect(model.rows.isEmpty)
        #expect(model.lastError == "There are no open tasks to plan.")
    }

    @Test @MainActor
    func load_surfacesClientFailure() async {
        let repository = InMemoryWorkItemRepository()
        await repository.seed(aiTask("First", order: "a1"))
        let model = DayPlanViewModel(
            repository: repository,
            calendar: aiTestWork,
            assistant: StubAssistant(failure: StubFailure()),
            clock: { aiTestNow }
        )

        await model.loadAndPlan()

        #expect(model.rows.isEmpty)
        #expect(model.lastError == "stub failure")
    }
}

// MARK: - Ask

struct AskViewModelTests {
    @Test @MainActor
    func ask_streamsTheAnswer() async throws {
        let model = AskViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: aiTestWork,
            assistant: StubAssistant(answerChunks: ["Hello", " world"]),
            clock: { aiTestNow }
        )
        model.question = "What’s left?"

        model.ask()
        let deadline = ContinuousClock.now + .seconds(2)
        while model.isAsking, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.answer == "Hello world")
        #expect(model.lastError == nil)
        #expect(!model.isAsking)
    }

    @Test @MainActor
    func ask_emptyQuestionDoesNothing() {
        let model = AskViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: aiTestWork,
            assistant: StubAssistant(answerChunks: ["Nope"]),
            clock: { aiTestNow }
        )
        model.question = "   "

        model.ask()

        #expect(model.answer.isEmpty)
        #expect(!model.isAsking)
    }

    @Test @MainActor
    func cancel_closesTheSheet() {
        let log = CompletionLog()
        let model = AskViewModel(
            repository: InMemoryWorkItemRepository(),
            calendar: aiTestWork,
            assistant: StubAssistant(),
            clock: { aiTestNow },
            onFinished: { [log] in log.record() }
        )

        model.cancel()

        #expect(log.count == 1)
    }
}

// MARK: - Detail breakdown

struct DetailBreakdownTests {
    @Test @MainActor
    func requestShowsSuggestionsAndAddCreatesChildren() async throws {
        let repository = InMemoryWorkItemRepository()
        let links = InMemoryLinkRepository()
        let attachments = InMemoryAttachmentRepository()
        let parent = WorkItem(
            kind: .task,
            title: "Ship the release",
            startAt: aiDate(9),
            endAt: aiDate(17)
        )
        await repository.seed(parent)

        let suggestions = [
            SubtaskSuggestion(title: "Write changelog", details: "Summarize changes.", estimatedMinutes: 20),
            SubtaskSuggestion(title: "Tag the build", details: "", estimatedMinutes: 5),
        ]
        let model = DetailViewModel(
            itemId: parent.id,
            repository: repository,
            linkRepository: links,
            attachmentRepository: attachments,
            calendar: aiTestWork,
            clock: { aiTestNow }
        )
        model.assistant = StubAssistant(subtasks: suggestions)
        await model.load()

        await model.requestBreakdown()
        #expect(model.subtaskSuggestions.map(\.title) == ["Write changelog", "Tag the build"])

        await model.addSubtasks([suggestions[0]])

        let children = await repository.children(of: parent.id)
        #expect(children.map(\.title) == ["Write changelog"])
        #expect(children.first?.kind == .subtask)
        #expect(children.first?.descriptionMd.contains("Estimated: 20 min") == true)
        #expect(model.subtaskSuggestions.isEmpty)
    }

    @Test @MainActor
    func requestFailureIsReported() async {
        let repository = InMemoryWorkItemRepository()
        let parent = WorkItem(title: "Parent", startAt: aiDate(9), endAt: aiDate(17))
        await repository.seed(parent)
        let model = DetailViewModel(
            itemId: parent.id,
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            calendar: aiTestWork,
            clock: { aiTestNow }
        )
        model.assistant = StubAssistant(failure: StubFailure())
        await model.load()

        await model.requestBreakdown()

        #expect(model.subtaskSuggestions.isEmpty)
        #expect(model.lastError == "stub failure")
    }
}

// MARK: - Settings model catalog

struct SettingsModelCatalogTests {
    @Test @MainActor
    func fetchModels_populatesThePicker() async {
        let model = SettingsViewModel(
            repository: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            calendar: aiTestCalendar,
            modelCatalog: StubCatalog(models: ["a", "b"])
        )

        await model.fetchModels()

        #expect(model.availableModels == ["a", "b"])
        #expect(model.lastError == nil)
    }

    @Test @MainActor
    func fetchModels_failureIsReported() async {
        let model = SettingsViewModel(
            repository: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            calendar: aiTestCalendar,
            modelCatalog: StubCatalog(failure: StubFailure())
        )

        await model.fetchModels()

        #expect(model.availableModels.isEmpty)
        #expect(model.lastError == "stub failure")
    }
}

private struct OverrideCatalog: AIModelCatalog {
    func listModels() async throws -> [String] { ["saved"] }
    func listModels(for settings: AIEndpointSettings) async throws -> [String] {
        settings.enabled ? ["edited-\(settings.model)"] : []
    }
}

@Test @MainActor
func fetchModels_usesTheCurrentFormBeforeSave() async {
    let model = SettingsViewModel(
        repository: InMemorySettingRepository(),
        keychain: InMemoryKeychainStore(),
        calendar: aiTestCalendar,
        modelCatalog: OverrideCatalog()
    )
    model.aiSettings.enabled = true
    model.aiSettings.model = "llama3.1:8b"

    await model.fetchModels()

    #expect(model.availableModels == ["edited-llama3.1:8b"])
}
