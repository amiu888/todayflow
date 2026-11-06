import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

private struct CorrectorStub: AIAssistant {
    var corrections: [String: String]

    func suggestTask(from objects: [RecognizedObject]) async throws -> TaskSuggestion {
        throw AIAssistantError.textCorrectionUnavailable
    }

    func breakDown(_ item: WorkItem) async throws -> [SubtaskSuggestion] {
        throw AIAssistantError.textCorrectionUnavailable
    }

    func planDay(_ items: [WorkItem], hours: WorkCalendar) async throws -> DayPlan {
        throw AIAssistantError.textCorrectionUnavailable
    }

    func ask(
        _ question: String,
        context: [WorkItem]
    ) async throws -> AsyncThrowingStream<String, Error> {
        throw AIAssistantError.textCorrectionUnavailable
    }

    func correctText(_ text: String) async throws -> String {
        corrections[text] ?? text
    }
}

@Suite("Detail grammar correction")
@MainActor
struct DetailGrammarTests {
    @Test func correctsTitleSummaryAndDescription() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(
            title: "teh report",
            descriptionMd: "the report are late",
            summary: "plese review"
        )
        await repository.seed(item)
        let model = DetailViewModel(
            itemId: item.id,
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository()
        )
        await model.load()
        model.corrector = CorrectorStub(corrections: [
            "teh report": "The report",
            "plese review": "Please review",
            "the report are late": "The report is late",
        ])

        await model.correctDraftText()

        #expect(model.lastError == nil)
        #expect(model.edit.title == "The report")
        #expect(model.edit.summary == "Please review")
        #expect(model.edit.descriptionMd == "The report is late")
        let stored = try #require(await repository.item(item.id))
        #expect(stored.title == "The report")
    }

    @Test func correctionFailureLeavesTextUntouched() async throws {
        let repository = InMemoryWorkItemRepository()
        let item = WorkItem(title: "teh report", summary: "plese review")
        await repository.seed(item)
        let model = DetailViewModel(
            itemId: item.id,
            repository: repository,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository()
        )
        await model.load()
        model.corrector = CorrectorStub(corrections: [
            "teh report": "The report",
        ])

        await model.correctDraftText()

        #expect(model.lastError == nil)
        #expect(model.edit.title == "The report")
        #expect(model.edit.summary == "plese review")
    }
}
