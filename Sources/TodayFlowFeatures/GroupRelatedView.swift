import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// Puts a task and the tasks related to it into one project.
public struct GroupRelatedView: View {
    @Bindable var model: GroupRelatedModel

    public init(model: GroupRelatedModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        destinationSection
                        relatedSection
                    }
                    .padding(18)
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: .infinity, minHeight: 420, idealHeight: 560, maxHeight: .infinity)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .onExitCommand { model.onCancel?() }
        .accessibilityIdentifier("group-related")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.badge.plus")
                .font(.title2)
                .foregroundStyle(DesignTokens.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Group related tasks")
                    .font(.headline)
                Text(model.target.map { "Starting from “\($0.title)”" } ?? " ")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Where

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Put them in")
            HStack(spacing: 10) {
                Picker("", selection: $model.destination) {
                    Text("A new project").tag(GroupRelatedModel.Destination.newProject)
                    if !model.projects.isEmpty {
                        Divider()
                        ForEach(model.projects) { project in
                            Text(project.title).tag(GroupRelatedModel.Destination.existing(project.id))
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Project")

                if model.destination == .newProject {
                    TextField("Project name", text: $model.newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("New project name")
                }
            }
        }
    }

    // MARK: - Which

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle(model.suggestions.isEmpty ? "Related tasks" : "Related tasks (\(model.suggestions.count))")
                Spacer()
                if !model.suggestions.isEmpty {
                    Button(model.selected.count == model.suggestions.count ? "Select None" : "Select All") {
                        if model.selected.count == model.suggestions.count {
                            model.selected = []
                        } else {
                            model.selected = Set(model.suggestions.map(\.id))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            if model.suggestions.isEmpty {
                Text("No related tasks found (same ticket, email thread, contact or tags). You can still put this task in a project.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.suggestions) { suggestion in
                        suggestionRow(suggestion)
                        if suggestion.id != model.suggestions.last?.id { Divider() }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DesignTokens.Palette.surface)
                )
            }
        }
    }

    private func suggestionRow(_ suggestion: RelatedSuggestion) -> some View {
        let isOn = model.selected.contains(suggestion.id)
        let elsewhere = model.project(of: suggestion.item)
        return Button {
            model.toggle(suggestion.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.body)
                    .foregroundStyle(isOn ? DesignTokens.Palette.accent : DesignTokens.Palette.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.item.title)
                        .font(.body)
                        .strikethrough(suggestion.item.status.isTerminal, color: DesignTokens.Palette.textSecondary)
                        .foregroundStyle(DesignTokens.Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        ForEach(suggestion.reasons, id: \.self) { reason in
                            Text(reason)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DesignTokens.Palette.accent.opacity(0.14), in: Capsule())
                                .foregroundStyle(DesignTokens.Palette.accent)
                        }
                        if let elsewhere {
                            Text("now in \(elsewhere.title)")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                        }
                        if suggestion.item.status.isTerminal {
                            Text("done")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(suggestion.reasons.joined(separator: ", "))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.Palette.textSecondary)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { model.onCancel?() }
                .keyboardShortcut(.cancelAction)
            Button(model.applyTitle) { Task { await model.apply() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApply)
                .accessibilityIdentifier("group-related-apply")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
