import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowAI

// MARK: - Mock transport

private actor MockAITransport: AITransport {
    struct Response {
        let status: Int
        let body: String
    }

    private var responses: [Response]
    private var streamResponses: [[String]]
    private(set) var requests: [URLRequest] = []
    private(set) var streamRequests: [URLRequest] = []

    init(responses: [Response] = [], streams: [[String]] = []) {
        self.responses = responses
        self.streamResponses = streams
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else {
            throw AIError.transport("No scripted response.")
        }
        let response = responses.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(response.body.utf8), http)
    }

    func stream(_ request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        streamRequests.append(request)
        guard !streamResponses.isEmpty else {
            throw AIError.transport("No scripted stream.")
        }
        let lines = streamResponses.removeFirst()
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }
}

private final class DelayLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [AIRequestInfo] = []

    func record(_ value: AIRequestInfo) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [AIRequestInfo] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

// MARK: - Fixtures

private let aiConfig = AIConfiguration(
    baseURL: URL(string: "https://ai.example.com/v1")!,
    apiKey: "test-key",
    model: "test-model",
    timeout: 5,
    sendAttachmentText: false
)

private func assistant(
    responses: [MockAITransport.Response],
    streams: [[String]] = [],
    delays: DelayLog = DelayLog(),
    requests: RequestLog = RequestLog(),
    configuration: AIConfiguration = aiConfig
) -> (OpenAICompatibleAssistant, MockAITransport, DelayLog, RequestLog) {
    let transport = MockAITransport(responses: responses, streams: streams)
    let assistant = OpenAICompatibleAssistant(
        configuration: configuration,
        transport: transport,
        sleeper: { delays.record($0) },
        onRequest: { requests.record($0) }
    )
    return (assistant, transport, delays, requests)
}

private func chatResponse(_ content: String) -> String {
    let object: [String: Any] = [
        "choices": [
            ["message": ["content": content]],
        ],
    ]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private func streamResponse(_ content: String) -> String {
    chatResponse(content)
}

private func errorResponse(_ message: String) -> String {
    let object: [String: Any] = ["error": ["message": message]]
    let data = try! JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private func bodyObject(_ request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

private func item(_ title: String, id: UUIDv7 = .new()) -> WorkItem {
    WorkItem(
        id: id,
        title: title,
        startAt: Date(timeIntervalSince1970: 1_800_000_000),
        endAt: Date(timeIntervalSince1970: 1_800_020_000),
        displayOrder: "a1"
    )
}

// MARK: - Tests

struct OpenAICompatibleAssistantTests {
    @Test func suggestTask_parsesJSONAndSendsAuthAndSchema() async throws {
        let payload = """
        {"title":"Review contract","summary":"Check the redlines.","priority":"P2","actions":["Open the PDF"]}
        """
        let (assistant, transport, _, requests) = assistant(
            responses: [.init(status: 200, body: chatResponse(payload))]
        )

        let suggestion = try await assistant.suggestTask(from: [
            RecognizedObject(
                type: .file,
                uti: "com.adobe.pdf",
                displayName: "contract.pdf",
                suggestedTitle: "contract"
            )
        ])

        #expect(suggestion.title == "Review contract")
        #expect(suggestion.summary == "Check the redlines.")
        #expect(suggestion.priority == .high)
        #expect(suggestion.actions == ["Open the PDF"])

        let sent = await transport.requests
        #expect(sent.count == 1)
        #expect(sent.first?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")

        let body = bodyObject(sent[0])
        #expect(body["model"] as? String == "test-model")
        #expect(body["stream"] as? Bool == false)
        let format = body["response_format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")

        // The "What was sent" record never contains the key.
        #expect(requests.all.count == 1)
        #expect(!requests.all[0].body.contains("test-key"))
        #expect(requests.all[0].body.contains("contract.pdf"))
    }

    @Test func suggestTask_fallsBackToJSONObjectWhenSchemaIsRejected() async throws {
        let payload = """
        {"title":"Review contract","summary":"","priority":"P3","actions":[]}
        """
        let (assistant, transport, _, _) = assistant(responses: [
            .init(status: 400, body: errorResponse("response_format json_schema unsupported")),
            .init(status: 200, body: chatResponse(payload)),
        ])

        _ = try await assistant.suggestTask(from: [
            RecognizedObject(type: .text, displayName: "Pasted text", suggestedTitle: "Review")
        ])

        let sent = await transport.requests
        #expect(sent.count == 2)
        let secondFormat = bodyObject(sent[1])["response_format"] as? [String: Any]
        #expect(secondFormat?["type"] as? String == "json_object")
    }

    @Test func suggestTask_fallsBackToProseJSONWhenFormatsAreRejected() async throws {
        let prose = """
        Here is the task:
        ```json
        {"title":"Send the report","summary":"","priority":"P1","actions":[]}
        ```
        """
        let (assistant, transport, _, _) = assistant(responses: [
            .init(status: 400, body: errorResponse("unsupported")),
            .init(status: 400, body: errorResponse("unsupported")),
            .init(status: 200, body: chatResponse(prose)),
        ])

        let suggestion = try await assistant.suggestTask(from: [
            RecognizedObject(type: .text, displayName: "Pasted text", suggestedTitle: "Report")
        ])

        #expect(suggestion.title == "Send the report")
        #expect(suggestion.priority == .urgent)
        #expect(await transport.requests.count == 3)
        #expect(bodyObject(await transport.requests[2])["response_format"] == nil)
    }

    @Test func suggestTask_retriesServerErrorsWithBackoff() async throws {
        let payload = """
        {"title":"Retry me","summary":"","priority":"P3","actions":[]}
        """
        let delays = DelayLog()
        let (assistant, transport, _, _) = assistant(
            responses: [
                .init(status: 500, body: errorResponse("boom")),
                .init(status: 200, body: chatResponse(payload)),
            ],
            delays: delays
        )

        let suggestion = try await assistant.suggestTask(from: [
            RecognizedObject(type: .text, displayName: "Pasted text")
        ])

        #expect(suggestion.title == "Retry me")
        #expect(await transport.requests.count == 2)
        #expect(delays.all == [0.5])
    }

    @Test func suggestTask_privacyToggleControlsAttachmentText() async throws {
        let privateConfig = AIConfiguration(
            baseURL: aiConfig.baseURL,
            apiKey: "test-key",
            model: "test-model",
            sendAttachmentText: false
        )
        let publicConfig = AIConfiguration(
            baseURL: aiConfig.baseURL,
            apiKey: "test-key",
            model: "test-model",
            sendAttachmentText: true
        )
        let object = RecognizedObject(
            type: .text,
            displayName: "Pasted text",
            suggestedTitle: "Note",
            previewText: "secret contents"
        )
        let payload = """
        {"title":"Note","summary":"","priority":"P3","actions":[]}
        """

        let (privateAssistant, privateTransport, _, _) = assistant(
            responses: [.init(status: 200, body: chatResponse(payload))],
            configuration: privateConfig
        )
        _ = try await privateAssistant.suggestTask(from: [object])
        let privateBody = String(decoding: await privateTransport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(!privateBody.contains("secret contents"))

        let (publicAssistant, publicTransport, _, _) = assistant(
            responses: [.init(status: 200, body: chatResponse(payload))],
            configuration: publicConfig
        )
        _ = try await publicAssistant.suggestTask(from: [object])
        let publicBody = String(decoding: await publicTransport.requests[0].httpBody ?? Data(), as: UTF8.self)
        #expect(publicBody.contains("secret contents"))
    }

    @Test func breakDown_parsesSnakeCaseSubtasks() async throws {
        let payload = """
        {"subtasks":[{"title":"Draft","details":"Write a draft.","estimated_minutes":45},{"title":"Review","details":"","estimated_minutes":15}]}
        """
        let (assistant, _, _, _) = assistant(
            responses: [.init(status: 200, body: chatResponse(payload))]
        )

        let subtasks = try await assistant.breakDown(item("Proposal"))

        #expect(subtasks.map(\.title) == ["Draft", "Review"])
        #expect(subtasks.first?.estimatedMinutes == 45)
        #expect(subtasks.first?.details == "Write a draft.")
    }

    @Test func planDay_ignoresUnknownIDsAndKeepsEveryRealTask() async throws {
        let first = WorkItem(title: "First", displayOrder: "a1")
        let second = WorkItem(title: "Second", displayOrder: "a2")
        let unknown = UUID()
        let payload = """
        {"summary":"Do the hard thing first.","order":[{"id":"\(second.id)","reason":"Due first"},{"id":"\(unknown.uuidString)","reason":"Hallucinated"}]}
        """
        let (assistant, _, _, _) = assistant(
            responses: [.init(status: 200, body: chatResponse(payload))]
        )

        let plan = try await assistant.planDay([first, second], hours: .standard)

        #expect(plan.summary == "Do the hard thing first.")
        #expect(plan.order.map(\.itemId) == [second.id, first.id])
        #expect(plan.order.first?.reason == "Due first")
        #expect(plan.order.last?.reason == "Not ordered by the model.")
    }

    @Test func ask_streamsSSEDeltas() async throws {
        let (assistant, transport, _, _) = assistant(
            responses: [],
            streams: [[
                #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#,
                #"data: {"choices":[{"delta":{"content":" world"}}]}"#,
                "data: [DONE]",
            ]]
        )

        let stream = try await assistant.ask("What's left?", context: [item("First")])
        var answer = ""
        for try await chunk in stream {
            answer += chunk
        }

        #expect(answer == "Hello world")
        #expect(await transport.streamRequests.count == 1)
        #expect(bodyObject(await transport.streamRequests[0])["stream"] as? Bool == true)
    }

    @Test func ask_parsesNonStreamingJSONFallback() async throws {
        let json = chatResponse("All done.")
        let (assistant, _, _, _) = assistant(
            responses: [],
            streams: [[json]]
        )

        let stream = try await assistant.ask("Status?", context: [])
        var answer = ""
        for try await chunk in stream {
            answer += chunk
        }

        #expect(answer == "All done.")
    }

    @Test func listModels_returnsSortedIDs() async throws {
        let body = #"{"data":[{"id":"b-model"},{"id":"a-model"}]}"#
        let (assistant, transport, _, _) = assistant(
            responses: [.init(status: 200, body: body)]
        )

        let models = try await assistant.listModels()

        #expect(models == ["a-model", "b-model"])
        #expect(await transport.requests.first?.httpMethod == "GET")
    }

    @Test func malformedContent_throwsReadableError() async throws {
        let (assistant, _, _, _) = assistant(
            responses: [.init(status: 200, body: chatResponse("not json at all"))]
        )

        do {
            _ = try await assistant.suggestTask(from: [
                RecognizedObject(type: .text, displayName: "Pasted text")
            ])
            Issue.record("Expected a malformed-response error")
        } catch let error as AIError {
            guard case .malformedResponse = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
    }

    @Test func promptTemplates_areBundled() {
        let library = PromptLibrary()
        #expect(library.text(PromptLibrary.suggest).contains("{{objects}}"))
        #expect(library.text(PromptLibrary.breakDown).contains("{{task}}"))
        #expect(library.text(PromptLibrary.planDay).contains("{{tasks}}"))
        #expect(library.text(PromptLibrary.ask).contains("{{context}}"))
    }
}

// MARK: - Email summary

@Test func summarizeEmail_sendsTheEmailAndReturnsProse() async throws {
    let (assistant, transport, _, requests) = assistant(
        responses: [.init(
            status: 200,
            body: chatResponse("Carol needs the vendor totals by Friday.")
        )]
    )
    let digest = EmailDigest(
        subject: "Q3 budget review",
        sender: "Carol <carol@example.com>",
        recipients: "Afonso <afonso@example.com>",
        body: "Please review the Q3 budget and send the vendor totals by Friday.",
        sourceApp: "com.apple.mail"
    )

    let summary = try await assistant.summarize(digest)

    #expect(summary == "Carol needs the vendor totals by Friday.")
    let sent = await transport.requests
    #expect(sent.count == 1)
    let body = bodyObject(sent[0])
    #expect(body["stream"] as? Bool == false)
    #expect(body["response_format"] == nil)
    let messages = body["messages"] as? [[String: String]]
    let prompt = messages?.last?["content"] ?? ""
    #expect(prompt.contains("Q3 budget review"))
    #expect(prompt.contains("carol@example.com"))
    #expect(prompt.contains("vendor totals"))
    #expect(requests.all.first?.feature == "summarize_email")
}

@Test func summarizeEmail_rejectsAnEmptyEmail() async {
    let (assistant, _, _, _) = assistant(responses: [])
    await #expect(throws: AIError.self) {
        _ = try await assistant.summarize(EmailDigest(subject: " ", body: " "))
    }
}
