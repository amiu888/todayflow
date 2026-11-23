#if canImport(FoundationModels)
import Foundation
import FoundationModels
import TodayFlowCore

/// On-device Apple Intelligence rewriter (macOS 26+). No network, no API key.
@available(macOS 26.0, *)
public struct AppleTextRewriter: TextRewriting {
    public init() {}

    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public func rewrite(_ original: String, conversation: [RewriteTurn]) async throws -> RewriteReply {
        guard let latest = conversation.last else {
            throw AIError.invalidConfiguration("There is no request.")
        }
        let session = LanguageModelSession(instructions: PromptLibrary().text(PromptLibrary.rewriteText))
        // The current version is the last answered turn, else the original.
        let current = conversation.dropLast().last(where: { $0.text?.isEmpty == false })?.text ?? original
        let earlier = conversation.dropLast().map { "- \($0.request)" }.joined(separator: "\n")
        let prompt = """
            Original text:
            <<<
            \(String(original.prefix(6_000)))
            >>>

            Current version:
            <<<
            \(String(current.prefix(6_000)))
            >>>
            \(earlier.isEmpty ? "" : "\nEarlier requests (already applied):\n\(earlier)\n")
            Request: \(latest.request)
            """
        let response = try await session.respond(to: prompt)
        let reply = RewriteReply.parse(response.content)
        guard !reply.text.isEmpty || reply.note != nil else {
            throw AIError.malformedResponse("The rewrite was empty.")
        }
        return reply
    }
}
#endif
