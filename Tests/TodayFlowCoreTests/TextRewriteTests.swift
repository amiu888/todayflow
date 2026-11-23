import Testing
@testable import TodayFlowCore

@Suite("Rewrite replies")
struct TextRewriteTests {
    @Test func readsNoteAndText() {
        let reply = RewriteReply.parse("""
            NOTE: Made it more formal and fixed the date.
            TEXT:
            Dear Alex,

            Please confirm by Friday.
            """)
        #expect(reply.note == "Made it more formal and fixed the date.")
        #expect(reply.text == "Dear Alex,\n\nPlease confirm by Friday.")
    }

    @Test func aReplyWithoutLabelsIsAllText() {
        #expect(RewriteReply.parse("  Please confirm by Friday.  ") == RewriteReply(text: "Please confirm by Friday."))
    }

    @Test func dropsReasoningAndCodeFences() {
        let reply = RewriteReply.parse("<think>hmm, formal…</think>\n```text\nNOTE: none\nTEXT: Hello team.\n```")
        #expect(reply.text == "Hello team.")
        #expect(reply.note == nil)
    }

    @Test func aNoteOnlyReplyKeepsTheNote() {
        let reply = RewriteReply.parse("NOTE: The text is already clear.")
        #expect(reply.text.isEmpty)
        #expect(reply.note == "The text is already clear.")
    }
}
