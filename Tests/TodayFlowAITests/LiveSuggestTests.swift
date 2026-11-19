import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowAI

/// Tries the suggest prompt on a real model. Off unless asked:
/// `TODAYFLOW_LIVE_AI_URL=http://127.0.0.1:8080/v1 TODAYFLOW_LIVE_AI_MODEL=<model> swift test --filter LiveSuggest`
struct LiveSuggestTests {
    static let url = ProcessInfo.processInfo.environment["TODAYFLOW_LIVE_AI_URL"]
    static let model = ProcessInfo.processInfo.environment["TODAYFLOW_LIVE_AI_MODEL"]

    @Test(.enabled(if: url != nil && model != nil))
    func realModel_titlesAChangeEmailAndALink() async throws {
        let assistant = OpenAICompatibleAssistant(configuration: AIConfiguration(
            baseURL: URL(string: Self.url!)!, model: Self.model!, timeout: 120, sendAttachmentText: true
        ))
        let email = RecognizedObject(
            type: .email, displayName: "RE: Approval needed", sourceApp: "com.microsoft.Outlook",
            metadata: ["from": "Ops Team <ops@example.com>"],
            suggestedTitle: "RE: Approval needed - weekend maintenance",
            previewText: "Hi Alex, please approve change CHG0045678 so we can patch the VPN gateways this Saturday 22:00–02:00. CAB meets Thursday; we need your approval by Wednesday noon. Thanks, Ops"
        )
        let examples = [TitleExample(
            kindKey: "email|change|com.microsoft.outlook", objectName: "Approval needed - DB failover",
            suggestedTitle: "Approve change", finalTitle: "CHG0011111: Approve DB failover test (by Tue)",
            finalDescription: "Ops needs CAB approval before Tuesday."
        )]
        let a = try await assistant.suggestTask(from: [email], examples: examples)
        print("EMAIL  title: \(a.title)\n       desc:  \(a.summary)")
        #expect(a.title.hasPrefix("CHG0045678"))

        let link = RecognizedObject(
            type: .url, displayName: "Pricing - Example Cloud", reference: "https://example.com/pricing",
            metadata: ["domain": "example.com", "pageTitle": "Pricing - Example Cloud"],
            suggestedTitle: "Pricing - Example Cloud",
            previewText: "Example Cloud pricing. Starter $12/month per seat, Business $30/month per seat. Annual plans save 20%. Free trial 14 days."
        )
        let b = try await assistant.suggestTask(from: [link], examples: [])
        print("LINK   title: \(b.title)\n       desc:  \(b.summary)")
        #expect(!b.title.isEmpty)
    }
}
