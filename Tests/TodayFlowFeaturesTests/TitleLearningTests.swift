import Foundation
import Testing
import TodayFlowCore
import TodayFlowRecognition
@testable import TodayFlowFeatures

/// A suggester that records the examples it was given.
private actor RecordingSuggester: TaskSuggesting {
    private(set) var receivedExamples: [[TitleExample]] = []
    let reply: TaskSuggestion
    init(reply: TaskSuggestion) { self.reply = reply }
    func suggestTask(from objects: [RecognizedObject], examples: [TitleExample]) async throws -> TaskSuggestion {
        receivedExamples.append(examples)
        return reply
    }
}

private struct NoFileAccess: FileAccess {
    func isDirectory(_ url: URL) -> Bool? { nil }
    func size(of url: URL) -> Int64? { nil }
    func modificationDate(of url: URL) -> Date? { nil }
    func copy(from source: URL, to destination: URL) throws {}
    func write(_ data: Data, to url: URL) throws {}
    func securityScopedBookmark(for url: URL) -> Data? { nil }
    func url(fromSecurityScopedBookmark data: Data) -> URL? { nil }
    func createDirectory(_ url: URL) throws {}
}

@MainActor
struct TitleLearningTests {
    private func makeModel(examples: TitleExampleStore, suggester: RecordingSuggester) -> CaptureViewModel {
        let model = CaptureViewModel(
            repository: InMemoryWorkItemRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            materializer: Materializer(
                fileAccess: NoFileAccess(),
                attachmentsDirectory: URL(fileURLWithPath: "/tmp/todayflow-title-learning")
            )
        )
        model.titleExamples = examples
        model.assistant = suggester
        return model
    }

    private let email = RecognizedObject(
        type: .email, displayName: "Approve patch", sourceApp: "com.microsoft.Outlook",
        reference: "message://x", suggestedTitle: "RE: Approve CHG0045678 patch window"
    )

    @Test func aCorrectedTitle_isRecorded_andSentWithTheNextDropOfTheSameKind() async throws {
        let store = TitleExampleStore(settings: InMemorySettingRepository())
        let suggester = RecordingSuggester(reply: TaskSuggestion(title: "CHG0045678: Approve patch window", summary: "Ops asks before Friday."))

        let first = makeModel(examples: store, suggester: suggester)
        first.prepare(dropped: [], recognized: [email])
        await first.requestAISuggestion()
        #expect(first.draft.title == "CHG0045678: Approve patch window")
        first.draft.title = "CHG0045678: Patch VPN gateways (approve by Fri)"
        await first.save()

        let saved = await store.all()
        #expect(saved.count == 1)
        #expect(saved.first?.suggestedTitle == "CHG0045678: Approve patch window")
        #expect(saved.first?.finalTitle == "CHG0045678: Patch VPN gateways (approve by Fri)")
        #expect(saved.first?.corrected == true)

        let second = makeModel(examples: store, suggester: suggester)
        second.prepare(dropped: [], recognized: [email])
        await second.requestAISuggestion()
        let sent = await suggester.receivedExamples
        #expect(sent.count == 2)
        #expect(sent[0].isEmpty)
        #expect(sent[1].first?.finalTitle == "CHG0045678: Patch VPN gateways (approve by Fri)")
    }
}
