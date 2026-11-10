import Foundation
import Testing
import TodayFlowRecognition

/// Builds `org.chromium.web-custom-data` bytes the way Chrome writes them.
private func chromiumPickle(_ entries: [(String, String)]) -> Data {
    var payload = Data()
    func appendUInt32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) }
    }
    func appendString16(_ string: String) {
        let units = Array(string.utf16)
        appendUInt32(UInt32(units.count))
        for unit in units {
            withUnsafeBytes(of: unit.littleEndian) { payload.append(contentsOf: $0) }
        }
        while payload.count % 4 != 0 { payload.append(0) }
    }
    appendUInt32(UInt32(entries.count))
    for (type, value) in entries {
        appendString16(type)
        appendString16(value)
    }
    var data = Data()
    withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
    data.append(payload)
    return data
}

@Suite("Web custom drag data")
struct WebCustomDataTests {
    @Test func readsChromiumPickleEntries() {
        let data = chromiumPickle([("application/x-card", "{\"a\":1}"), ("text/x-odd", "é")])
        let entries = WebCustomData.entries(from: data)
        #expect(entries.map(\.type) == ["application/x-card", "text/x-odd"])
        #expect(entries.map(\.value) == ["{\"a\":1}", "é"])
    }

    @Test func findsAJiraURLInsideACardPayload() {
        let json = #"{"issueKey":"ABC-42","url":"https:\/\/acme.atlassian.net\/browse\/ABC-42","summary":"Fix login"}"#
        let data = chromiumPickle([("application/vnd.jira.card", json)])
        #expect(WebCustomData.jiraIssueURL(from: data)?.absoluteString
            == "https://acme.atlassian.net/browse/ABC-42")
        #expect(WebCustomData.cardSummary(from: data) == "Fix login")
    }

    @Test func buildsTheURLFromAKeyAndASite() {
        let json = #"{"key":"OPS-7","baseUrl":"https://acme.atlassian.net","title":"Rotate keys"}"#
        let data = chromiumPickle([("application/x-pdnd-card", json)])
        #expect(WebCustomData.jiraIssueURL(from: data)?.absoluteString
            == "https://acme.atlassian.net/browse/OPS-7")
    }

    @Test func fallsBackToRawUTF16WhenTheFormatIsUnknown() throws {
        let raw = try #require("xx https://jira.example.com/browse/WEB-9 xx".data(using: .utf16LittleEndian))
        #expect(WebCustomData.jiraIssueURL(from: raw)?.absoluteString
            == "https://jira.example.com/browse/WEB-9")
    }

    @Test func ignoresDataWithoutAJiraIssue() {
        let data = chromiumPickle([("application/x-thing", "{\"id\":5,\"name\":\"ABC-1 widget\"}")])
        #expect(WebCustomData.jiraIssueURL(from: data) == nil)
        #expect(WebCustomData.entries(from: Data([1, 2])).isEmpty)
    }
}
