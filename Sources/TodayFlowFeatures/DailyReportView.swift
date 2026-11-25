import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// Daily Report: today's work in a short report for management. The text
/// is editable; Copy, Email and Save send exactly what is shown.
public struct DailyReportView: View {
    @Bindable var model: DailyReportModel

    public init(model: DailyReportModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            options
            Divider()
            editor
            Divider()
            footer
        }
        .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity, minHeight: 440, idealHeight: 620, maxHeight: .infinity)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
        .accessibilityIdentifier("daily-report")
    }

    // MARK: - Header: day and counts

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { model.previousDay() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Previous day")
                    .accessibilityLabel("Previous day")
                Text(model.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.headline)
                Button { model.nextDay() } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .disabled(model.isToday)
                    .help("Next day")
                    .accessibilityLabel("Next day")
                if !model.isToday {
                    Button("Today") { model.goToToday() }
                        .controlSize(.small)
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 8) {
                count(model.report.completed.count, "Completed", "checkmark.circle.fill", .green)
                count(model.report.inProgress.count, "In progress", "circle.lefthalf.filled", DesignTokens.Palette.accent)
                count(model.report.blocked.count, "Blocked", "exclamationmark.circle", .red)
                count(model.report.carriedOver.count, "Carried over", "arrow.uturn.right", .orange)
            }
        }
        .padding(12)
    }

    private func count(_ value: Int, _ label: String, _ symbol: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(color)
                Text("\(value)").font(.title3.weight(.semibold).monospacedDigit())
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignTokens.Palette.textSecondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Toggle("Notes", isOn: $model.includeNotes)
                    .help("Add the latest note written that day under each task")
                Toggle("Priority", isOn: $model.includePriority)
                    .help("Show P1–P4 next to each task")
                Toggle("Planned next", isOn: $model.includeNextUp)
                    .help("List what is due on the next working day")
                Toggle("Markdown", isOn: $model.markdown)
                    .help("Use Markdown headings and bullets (for Teams, Slack, Obsidian)")
                Spacer(minLength: 0)
            }
            .checkboxToggleStyle()
            .font(.callout)
            HStack(spacing: 8) {
                Text("From")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                TextField("Your name and team (optional)", text: $model.author)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer(minLength: 0)
                if model.isEdited {
                    Text("Edited")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .help("Your edits are kept. Start Over rebuilds the report from your tasks.")
                    Button("Start Over") { model.startOver() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Report text

    private var editor: some View {
        TextEditor(text: $model.text)
            .font(.system(.body, design: model.markdown ? .monospaced : .default))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(DesignTokens.Palette.surface)
            .accessibilityLabel("Report text")
    }

    // MARK: - Actions

    private var footer: some View {
        HStack(spacing: 10) {
            AIRewriteButton(text: model.text, field: "Daily report", applyTitle: "Use This") { model.text = $0 }
            Text("Check and edit the text, then send it.")
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Save…") { model.save() }
                .help("Save the report as a text or Markdown file")
            Button("Email…") { model.email() }
                .help("Open a new email with this report")
            Button(model.copied ? "Copied" : "Copy") { model.copy() }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .help("Copy the report to paste into email, Teams or Slack (⌘↩)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
