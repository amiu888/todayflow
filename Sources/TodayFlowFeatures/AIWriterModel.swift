import Foundation
import Observation
import TodayFlowCore

/// The AI Writer: one piece of text, a chat of requests ("more formal"),
/// and a version per answer. Nothing changes in the task until Replace.
@MainActor
@Observable
public final class AIWriterModel {
    public let original: String
    /// What is being rewritten ("Summary", "Note", "Selected text").
    public let fieldName: String
    public let applyTitle: String

    public private(set) var turns: [RewriteTurn] = []
    /// Index into `answered`, or nil while showing the original.
    public private(set) var versionIndex: Int?
    /// The suggestion as shown and edited on the right.
    public var draft: String
    public var chatText = ""
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    @ObservationIgnored public var rewriter: (any TextRewriting)? {
        didSet { isAvailable = rewriter != nil }
    }
    /// False when AI is off (the window explains how to turn it on).
    public private(set) var isAvailable = false
    /// True until the app has looked up the AI settings.
    public var isResolvingAI = true

    @ObservationIgnored public var onApply: (@MainActor (String) -> Void)?
    @ObservationIgnored public var onClose: (@MainActor () -> Void)?
    @ObservationIgnored public var onOpenSettings: (@MainActor () -> Void)?

    public init(original: String, fieldName: String, applyTitle: String = "Replace") {
        self.original = original
        self.fieldName = fieldName
        self.applyTitle = applyTitle
        self.draft = ""
    }

    /// Turns that have an answer with text, oldest first.
    public var answered: [RewriteTurn] { turns.filter { $0.text != nil } }

    public var hasSuggestion: Bool { versionIndex != nil }

    public var versionLabel: String {
        guard let versionIndex else { return "Original" }
        return "Version \(versionIndex + 1) of \(answered.count)"
    }

    public var canApply: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft != original && !isWorking
    }

    public func send(_ preset: RewritePreset) async {
        await send(preset.request, shown: preset.label)
    }

    /// Sends the chat box text.
    public func sendChat() async {
        let text = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatText = ""
        await send(text, shown: text)
    }

    /// Asks for a new version. `shown` is what the chat shows for it.
    public func send(_ request: String, shown: String) async {
        guard let rewriter, !isWorking,
              !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // A hand edit of the suggestion becomes the version the AI refines.
        if let index = versionIndex, draft != answered[index].text,
           let turnIndex = turns.firstIndex(where: { $0.id == answered[index].id }) {
            turns[turnIndex].text = draft
        }
        var turn = RewriteTurn(request: request, label: shown == request ? nil : shown)
        turns.append(turn)
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let reply = try await rewriter.rewrite(original, conversation: turns)
            let current = versionIndex.map { answered[$0].text ?? original } ?? original
            turn.text = reply.text.isEmpty ? current : reply.text
            turn.note = reply.note
            turns[turns.count - 1] = turn
            versionIndex = answered.count - 1
            draft = turn.text ?? draft
        } catch {
            turns.removeLast()
            errorMessage = "The AI couldn’t answer: \(error.localizedDescription)"
        }
    }

    public func showVersion(_ delta: Int) {
        let count = answered.count
        guard count > 0 else { return }
        // -1 steps back to the original.
        let current = versionIndex ?? -1
        let next = min(max(current + delta, -1), count - 1)
        versionIndex = next < 0 ? nil : next
        draft = versionIndex.map { answered[$0].text ?? original } ?? ""
    }

    public func apply() {
        guard canApply else { return }
        onApply?(draft)
        onClose?()
    }

    public func cancel() {
        onClose?()
    }
}
