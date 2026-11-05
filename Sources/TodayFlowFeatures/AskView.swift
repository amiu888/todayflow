import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The "Ask about my tasks" sheet (driver.md §8). The answer is read-only;
/// nothing is created or changed. The request payload can be inspected through
/// the "What was sent" disclosure.
public struct AskView: View {
    private let model: AskViewModel
    private let sentPayload: (@MainActor () -> String?)?

    @State private var showsSent = false
    @FocusState private var isQuestionFocused: Bool

    public init(
        model: AskViewModel,
        sentPayload: (@MainActor () -> String?)? = nil
    ) {
        self.model = model
        self.sentPayload = sentPayload
    }

    @MainActor
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)

                Text("Ask about your tasks")
                    .font(.title3.weight(.semibold))

                Spacer()
            }

            HStack(spacing: 8) {
                TextField("What’s left for the launch?", text: Binding(
                    get: { model.question },
                    set: { model.question = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .focused($isQuestionFocused)
                .onSubmit { model.ask() }

                Button("Ask") {
                    model.ask()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isAsking
                        || model.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.answer.isEmpty && !model.isAsking {
                        Text("Answers use only the tasks in this app. Nothing is sent except the question and the task fields shown below.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(model.answer)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if model.isAsking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )

            if let error = model.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color(hex: "#fab219"))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let sentPayload, sentPayload() != nil {
                DisclosureGroup(isExpanded: $showsSent) {
                    ScrollView {
                        Text(sentPayload() ?? "")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 100)
                } label: {
                    Text("What was sent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()

                Button("Close") {
                    model.cancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 500, height: 520)
        .overlay(alignment: .top) { WindowDragGrabber() }
        .onAppear { isQuestionFocused = true }
    }
}
