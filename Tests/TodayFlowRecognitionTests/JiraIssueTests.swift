import Foundation
import Testing
import TodayFlowRecognition

@Suite("Jira issue drops")
struct JiraIssueTests {
    @Test func parsesBrowseURL() throws {
        let url = try #require(URL(string: "https://acme.atlassian.net/browse/ABC-123"))
        let issue = try #require(JiraIssueReference(url: url))
        #expect(issue.issueKey == "ABC-123")
        #expect(issue.projectKey == "ABC")
        #expect(issue.url == url)
    }

    @Test func parsesBoardURLWithSelectedIssue() throws {
        let url = try #require(URL(string:
            "https://acme.atlassian.net/jira/software/projects/ABC/boards/7?selectedIssue=ABC-42"
        ))
        #expect(JiraIssueReference(url: url)?.issueKey == "ABC-42")
    }

    @Test func rejectsNonIssueURLs() throws {
        let url = try #require(URL(string: "https://acme.atlassian.net/jira/software/projects/ABC/boards/7"))
        #expect(JiraIssueReference(url: url) == nil)
        let example = try #require(URL(string: "https://example.com/browse/ABC-123"))
        // A /browse/ path is still a strong Jira-shaped signal for self-hosted
        // Jira; a non-issue URL without the key is rejected.
        #expect(JiraIssueReference(url: example)?.issueKey == "ABC-123")
    }

    @Test func rejectsAKeyShapedPathOnANonJiraHost() throws {
        let url = try #require(URL(string: "https://example.com/products/ABC-123"))
        #expect(JiraIssueReference(url: url) == nil)
        let genericQuery = try #require(URL(string: "https://example.com/page?key=ABC-123"))
        #expect(JiraIssueReference(url: genericQuery) == nil)
        let jiraQuery = try #require(URL(string: "https://jira.example.com/page?key=ABC-123"))
        #expect(JiraIssueReference(url: jiraQuery)?.issueKey == "ABC-123")
        let selectedIssue = try #require(URL(string: "https://example.com/page?selectedIssue=ABC-123"))
        #expect(JiraIssueReference(url: selectedIssue)?.issueKey == "ABC-123")
    }

    @Test func findsIssueURLInsidePlainText() throws {
        let text = """
        ABC-123 Fix login timeout
        https://acme.atlassian.net/browse/ABC-123
        """
        #expect(JiraIssueReference.firstURL(in: text)?.absoluteString
            == "https://acme.atlassian.net/browse/ABC-123")
    }

    @Test func extractsSummaryFromCardText() {
        let text = """
        ABC-123
        Fix the login timeout
        """
        #expect(JiraIssueReference.summary(from: text, issueKey: "ABC-123")
            == "Fix the login timeout")
        #expect(JiraIssueReference.summary(
            from: "ABC-123 Fix the login timeout",
            issueKey: "ABC-123"
        ) == "Fix the login timeout")
    }

    @Test func recognizerBuildsAUsefulTaskTitle() throws {
        let url = try #require(URL(string: "https://acme.atlassian.net/browse/ABC-123"))
        let object = DroppedObject(
            url: url,
            text: "Fix the login timeout",
            sourceApp: "com.google.Chrome"
        )
        let recognizer = JiraIssueRecognizer()
        #expect(recognizer.canHandle(object))
        let recognized = recognizer.recognize(object)

        #expect(recognized.type == .url)
        #expect(recognized.displayName == "ABC-123")
        #expect(recognized.suggestedTitle == "ABC-123 · Fix the login timeout")
        #expect(recognized.reference == url.absoluteString)
        #expect(recognized.metadata[MetadataKeys.jiraIssueKey] == "ABC-123")
        #expect(recognized.metadata[MetadataKeys.jiraProjectKey] == "ABC")
        #expect(recognized.metadata[MetadataKeys.jiraSummary] == "Fix the login timeout")
    }

    @Test func recognizerFallsBackToTheIssueKey() throws {
        let url = try #require(URL(string: "https://jira.example.com/browse/OPS-9"))
        let recognized = JiraIssueRecognizer().recognize(
            DroppedObject(url: url)
        )
        #expect(recognized.suggestedTitle == "OPS-9")
        #expect(recognized.metadata[MetadataKeys.jiraIssueKey] == "OPS-9")
    }

    @Test func productionPipelineUsesTheJiraTitle() throws {
        let url = try #require(URL(string: "https://acme.atlassian.net/browse/ABC-123"))
        let draft = RecognitionPipeline.standard.process(
            [
                DroppedObject(
                    url: url,
                    text: "Fix the login timeout",
                    sourceApp: "com.google.Chrome"
                )
            ],
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(draft.title == "ABC-123 · Fix the login timeout")
        #expect(draft.objects.first?.reference == url.absoluteString)
        #expect(draft.objects.first?.metadata[MetadataKeys.jiraIssueKey] == "ABC-123")
    }

    @Test func genericLinkIsNotAJiraIssue() throws {
        let url = try #require(URL(string: "https://example.com/blog/post"))
        #expect(!JiraIssueRecognizer().canHandle(DroppedObject(url: url)))
    }
}
