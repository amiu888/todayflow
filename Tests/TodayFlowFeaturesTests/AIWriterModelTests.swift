import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowFeatures

/// Answers "v1", "v2"… and records every conversation it was sent.
private final class FakeRewriter: TextRewriting, @unchecked Sendable {
    var calls: [[RewriteTurn]] = []
    var fail = false
    var note: String?

    func rewrite(_ original: String, conversation: [RewriteTurn]) async throws -> RewriteReply {
        calls.append(conversation)
        if fail { throw URLError(.timedOut) }
        return RewriteReply(text: "v\(calls.count)", note: note)
    }
}

@MainActor
struct AIWriterModelTests {
    @Test func eachRequestMakesANewVersionAndKeepsTheChat() async {
        let ai = FakeRewriter()
        let model = AIWriterModel(original: "pls fix the server", fieldName: "Summary")
        model.rewriter = ai

        await model.send(.formal)
        #expect(model.draft == "v1")
        #expect(model.versionLabel == "Version 1 of 1")
        #expect(model.turns.first?.displayRequest == "More formal")
        // The AI gets the full instruction, the chat shows the label.
        #expect(ai.calls.first?.first?.request == RewritePreset.formal.request)

        model.chatText = "mention Friday"
        await model.sendChat()
        #expect(model.draft == "v2")
        #expect(model.chatText.isEmpty)
        // The second call carries the first answer, so it refines it.
        #expect(ai.calls.last?.count == 2)
        #expect(ai.calls.last?.first?.text == "v1")
        #expect(ai.calls.last?.last?.request == "mention Friday")
    }

    @Test func versionsStepBackToTheOriginal() async {
        let model = AIWriterModel(original: "original", fieldName: "Note")
        model.rewriter = FakeRewriter()
        await model.send(.shorter)
        await model.send(.clearer)

        model.showVersion(-1)
        #expect(model.draft == "v1")
        model.showVersion(-1)
        #expect(model.draft.isEmpty) // back to the original: nothing suggested
        #expect(!model.hasSuggestion)
        #expect(!model.canApply)
        model.showVersion(5)
        #expect(model.draft == "v2")
    }

    @Test func aHandEditIsWhatTheNextRequestRefines() async {
        let ai = FakeRewriter()
        let model = AIWriterModel(original: "original", fieldName: "Note")
        model.rewriter = ai
        await model.send(.formal)
        model.draft = "v1 edited by hand"
        await model.send(.shorter)
        #expect(ai.calls.last?.first?.text == "v1 edited by hand")
    }

    @Test func applyHandsBackTheChosenTextAndCloses() async {
        let model = AIWriterModel(original: "original", fieldName: "Title")
        model.rewriter = FakeRewriter()
        var applied: String?
        var closed = false
        model.onApply = { applied = $0 }
        model.onClose = { closed = true }

        model.apply()
        #expect(applied == nil) // nothing changed yet

        await model.send(.fixGrammar)
        model.apply()
        #expect(applied == "v1")
        #expect(closed)
    }

    @Test func aFailedRequestShowsAnErrorAndKeepsTheText() async {
        let ai = FakeRewriter()
        ai.fail = true
        let model = AIWriterModel(original: "original", fieldName: "Note")
        model.rewriter = ai
        await model.send(.formal)
        #expect(model.turns.isEmpty)
        #expect(model.draft.isEmpty)
        #expect(model.errorMessage != nil)
    }

    @Test func aNoteOnlyAnswerKeepsTheCurrentText() async {
        final class NoteOnly: TextRewriting, @unchecked Sendable {
            func rewrite(_ original: String, conversation: [RewriteTurn]) async throws -> RewriteReply {
                RewriteReply(text: "", note: "It is already clear.")
            }
        }
        let model = AIWriterModel(original: "original", fieldName: "Note")
        model.rewriter = NoteOnly()
        await model.send(.suggest)
        #expect(model.draft == "original")
        #expect(model.turns.last?.note == "It is already clear.")
    }
}
