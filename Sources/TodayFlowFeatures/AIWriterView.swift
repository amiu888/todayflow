import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The AI Writer window: the original on the left, the AI's version on the
/// right (editable), one-click styles, and a chat box for anything else.
public struct AIWriterView: View {
    @Bindable var model: AIWriterModel
    @FocusState private var chatFocused: Bool

    public init(model: AIWriterModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isResolvingAI {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !model.isAvailable {
                aiOffState
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    columns
                    if !model.turns.isEmpty { chatHistory }
                    if let error = model.errorMessage { errorLine(error) }
                    presets
                    chatBox
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 820, maxWidth: .infinity, minHeight: 480, idealHeight: 620, maxHeight: .infinity)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .onAppear { chatFocused = true }
        .onExitCommand { model.cancel() }
        .accessibilityIdentifier("ai-writer")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(DesignTokens.Palette.gradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("AI Writer")
                    .font(.headline)
                Text("Rewriting: \(model.fieldName). Nothing changes until you press \(model.applyTitle).")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Original and suggestion

    private var columns: some View {
        HStack(alignment: .top, spacing: 12) {
            originalPane
            suggestionPane
        }
        .frame(maxHeight: .infinity)
    }

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            paneTitle("Original", symbol: "doc.text")
            ScrollView {
                Text(model.original)
                    .font(.body)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(pane)
        }
    }

    private var suggestionPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                paneTitle(model.hasSuggestion ? "Suggestion" : "Suggestion appears here", symbol: "sparkles")
                Spacer()
                if !model.answered.isEmpty {
                    Button { model.showVersion(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(model.versionIndex == nil)
                        .help("Earlier version")
                    Text(model.versionLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    Button { model.showVersion(1) } label: { Image(systemName: "chevron.right") }
                        .disabled(model.versionIndex == model.answered.count - 1)
                        .help("Later version")
                }
            }
            .buttonStyle(.borderless)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .disabled(model.isWorking)
                    .accessibilityLabel("Suggestion")
                if model.draft.isEmpty && !model.isWorking {
                    Text("Pick a style below, or tell the AI what you want. You can also edit here yourself.")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignTokens.Palette.surface.opacity(0.92))
                        .allowsHitTesting(false)
                }
                if model.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Writing…").font(.callout)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DesignTokens.Palette.surface.opacity(0.85))
                }
            }
            .background(pane)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(model.hasSuggestion ? DesignTokens.Palette.accent.opacity(0.6) : DesignTokens.Palette.hairline)
            )
        }
    }

    private func paneTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.Palette.textSecondary)
    }

    private var pane: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(DesignTokens.Palette.surface)
    }

    // MARK: - Chat

    private var chatHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.turns) { turn in
                        HStack {
                            Spacer(minLength: 60)
                            Text(turn.displayRequest)
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(DesignTokens.Palette.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                        }
                        if let note = turn.note {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(DesignTokens.Palette.accent)
                                    .padding(.top, 4)
                                Text(note)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(DesignTokens.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                                Spacer(minLength: 60)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
            }
            // As tall as the conversation, up to about four messages.
            .frame(height: min(130, CGFloat(model.turns.count + model.turns.filter { $0.note != nil }.count) * 34))
            .onChange(of: model.turns.count) { proxy.scrollTo("end") }
        }
    }

    private func errorLine(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(2)
    }

    private var presets: some View {
        ChipFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(RewritePreset.allCases) { preset in
                Button {
                    Task { await model.send(preset) }
                } label: {
                    Label(preset.label, systemImage: preset.symbol)
                        .font(.callout)
                        .fixedSize()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isWorking)
                .accessibilityIdentifier("ai-writer-preset-\(preset.rawValue)")
            }
        }
    }

    private var chatBox: some View {
        HStack(spacing: 8) {
            TextField(
                "Tell the AI what you want, e.g. “more formal and mention the Friday deadline”",
                text: $model.chatText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .focused($chatFocused)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DesignTokens.Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(chatFocused ? DesignTokens.Palette.accent.opacity(0.7) : DesignTokens.Palette.hairline)
            )
            .onSubmit { Task { await model.sendChat() } }
            .accessibilityIdentifier("ai-writer-chat")

            Button {
                Task { await model.sendChat() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(model.isWorking || model.chatText.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Send (Return)")
        }
    }

    // MARK: - AI off

    private var aiOffState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            Text("AI is turned off")
                .font(.headline)
            Text("Turn on AI in Settings to rewrite text. Spell check still works in every text box.")
                .font(.callout)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .multilineTextAlignment(.center)
            if model.onOpenSettings != nil {
                Button("Open AI Settings") { model.onOpenSettings?() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.draft, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(model.draft.isEmpty)
            .help("Copy the suggestion")
            Spacer()
            Button("Cancel") { model.cancel() }
                .keyboardShortcut(.cancelAction)
            Button(model.applyTitle) { model.apply() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApply)
                .help("Use this text (⌘↩)")
                .accessibilityIdentifier("ai-writer-apply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
