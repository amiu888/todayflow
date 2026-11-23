import SwiftUI
import TodayFlowDesign

/// Opens the AI Writer for some text. The Mac app puts one in the
/// environment of task and New Task windows; without it, ✨ buttons hide.
public struct AIRewriteAction: Sendable {
    let handler: @MainActor @Sendable (_ text: String, _ field: String, _ applyTitle: String, _ apply: @escaping @MainActor (String) -> Void) -> Void

    public init(_ handler: @escaping @MainActor @Sendable (String, String, String, @escaping @MainActor (String) -> Void) -> Void) {
        self.handler = handler
    }

    @MainActor
    public func callAsFunction(
        _ text: String, field: String, applyTitle: String = "Replace",
        apply: @escaping @MainActor (String) -> Void
    ) {
        handler(text, field, applyTitle, apply)
    }
}

private struct AIRewriteKey: EnvironmentKey {
    static let defaultValue: AIRewriteAction? = nil
}

public extension EnvironmentValues {
    var aiRewrite: AIRewriteAction? {
        get { self[AIRewriteKey.self] }
        set { self[AIRewriteKey.self] = newValue }
    }
}

/// The ✨ Rewrite button shown next to text: opens the AI Writer, and
/// `apply` receives the version the person chooses.
struct AIRewriteButton: View {
    let text: String
    let field: String
    var applyTitle = "Replace"
    var compact = false
    let apply: @MainActor (String) -> Void

    @Environment(\.aiRewrite) private var aiRewrite

    var body: some View {
        if let aiRewrite {
            let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button {
                aiRewrite(text, field: field, applyTitle: applyTitle, apply: apply)
            } label: {
                if compact {
                    Image(systemName: "sparkles")
                } else {
                    Label("Rewrite", systemImage: "sparkles")
                        .font(.caption)
                        .fixedSize()
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isEmpty ? DesignTokens.Palette.textSecondary : DesignTokens.Palette.accent)
            .disabled(isEmpty)
            .help(isEmpty
                ? "Write something first, then rewrite it with AI"
                : "Rewrite \(field.lowercased()) with AI: more formal, shorter, fix grammar, or tell it what you want")
            .accessibilityLabel("Rewrite \(field) with AI")
        }
    }
}
