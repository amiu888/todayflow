import Foundation
import Testing
import TodayFlowFeatures

struct LinkInputTests {
    @Test func addsHttpsToABareAddress() {
        #expect(LinkInput.url(from: " example.com/page?x=1 ")?.absoluteString == "https://example.com/page?x=1")
        #expect(LinkInput.url(from: "localhost:3000/app")?.absoluteString == "https://localhost:3000/app")
    }

    @Test func keepsALinkThatAlreadyHasAScheme() {
        #expect(LinkInput.url(from: "http://192.168.1.95:8080/")?.absoluteString == "http://192.168.1.95:8080/")
        #expect(LinkInput.url(from: "mailto:someone@example.com")?.scheme == "mailto")
        #expect(LinkInput.url(from: "obsidian://open?vault=Notes")?.scheme == "obsidian")
    }

    @Test func rejectsTextThatIsNotALink() {
        #expect(LinkInput.url(from: "") == nil)
        #expect(LinkInput.url(from: "   ") == nil)
        #expect(LinkInput.url(from: "call the bank") == nil)
        #expect(LinkInput.url(from: "report") == nil)
        #expect(LinkInput.url(from: "https://") == nil)
    }
}
