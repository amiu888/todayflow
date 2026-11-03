import Foundation
import Testing
@testable import TodayFlowRecognition

@Suite("EmlParser")
struct EmlParserTests {
    /// A fixture with a folded Subject, an RFC 2047 encoded word, and a
    /// standard date line.
    private static let fixture = """
        From: Alice <alice@example.com>
        To: Bob <bob@example.com>
        Subject: =?UTF-8?Q?Re:_Project_=E2=82=AC_update?=
        Date: Mon, 05 Jan 2026 10:42:00 +0000
        Message-ID: <abc123@example.com>

        Hello Bob,

        The project update is attached.

        Alice
        """

    @Test("parsesHeadersAndBody")
    func parsesHeadersAndBody() {
        let message = EmlParser.parse(Self.fixture)

        #expect(message.from == "Alice <alice@example.com>")
        #expect(message.to == "Bob <bob@example.com>")
        #expect(message.subject == "Re: Project € update")
        #expect(message.messageId == "<abc123@example.com>")
        #expect(message.body?.hasPrefix("Hello Bob,") == true)
    }

    @Test("parsesDate")
    func parsesDate() {
        let message = EmlParser.parse(Self.fixture)

        guard let date = message.date else {
            Issue.record("date was not parsed")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 1)
        #expect(components.day == 5)
        #expect(components.hour == 10)
        #expect(components.minute == 42)
        #expect(components.second == 0)
    }

    @Test("decodesBase64EncodedWords")
    func decodesBase64EncodedWords() {
        // "Café" in UTF-8, base64.
        let text = "=?UTF-8?B?Q2Fmw6k=?="
        #expect(EmlParser.decodeEncodedWords(text) == "Café")
    }

    @Test("removesWhitespaceBetweenAdjacentEncodedWords")
    func removesWhitespaceBetweenAdjacentEncodedWords() {
        // "Grüße" split across two Q-words with a space between them.
        let text = "=?UTF-8?Q?Gr=C3=BC=C3=9F?= =?UTF-8?Q?e?=!"
        #expect(EmlParser.decodeEncodedWords(text) == "Grüße!")
    }

    @Test("unfoldsContinuationLines")
    func unfoldsContinuationLines() {
        let raw = "Subject: Hello\n World\nFrom: a@b"
        let unfolded = EmlParser.unfold(raw)
        #expect(unfolded == "Subject: HelloWorld\nFrom: a@b")
    }

    @Test("emptyInputYieldsEmptyMessage")
    func emptyInputYieldsEmptyMessage() {
        let message = EmlParser.parse("")
        #expect(message.subject == nil)
        #expect(message.body == nil)
    }
}
