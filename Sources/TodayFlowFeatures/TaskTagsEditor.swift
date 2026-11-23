import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The Tags section of a task window: every tag as a chip you can click to
/// rename or ✕ to remove, and an Add tag field that suggests tags used on
/// other tasks. Several tags can be added at once, separated by commas.
struct TaskTagsEditor<Trailing: View>: View {
    let tags: [String]
    let suggestions: @MainActor (String) -> [String]
    let onAdd: @MainActor (String) -> Void
    let onRename: @MainActor (String, String) -> Void
    let onRemove: @MainActor (String) -> Void
    @ViewBuilder var trailing: () -> Trailing

    @State private var newTag = ""
    @State private var editingTag: String?
    @State private var editText = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case add
        case edit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ChipFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    if editingTag == tag {
                        editChip(tag)
                    } else {
                        chip(tag)
                    }
                }
                addField
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if focus == .add {
                let matches = suggestions(newTag)
                if !matches.isEmpty {
                    suggestionRow(matches)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-tags")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("Tags")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            if !tags.isEmpty {
                Text("\(tags.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DesignTokens.Palette.surfaceRaised, in: Capsule())
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Spacer()
            trailing()
        }
    }

    // MARK: - Chips

    private func chip(_ tag: String) -> some View {
        HStack(spacing: 5) {
            Button {
                startEditing(tag)
            } label: {
                Text(tag)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Click to rename “\(tag)”")
            .accessibilityLabel("Tag \(tag)")
            .accessibilityHint("Rename")

            Button {
                onRemove(tag)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Palette.accent.opacity(0.7))
            .help("Remove tag “\(tag)”")
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(DesignTokens.Palette.accent.opacity(0.14)))
        .overlay(Capsule().stroke(DesignTokens.Palette.accent.opacity(0.25), lineWidth: 0.5))
        .foregroundStyle(DesignTokens.Palette.accent)
        .fixedSize()
        .contextMenu {
            Button("Rename…") { startEditing(tag) }
            Button("Remove", role: .destructive) { onRemove(tag) }
        }
    }

    private func editChip(_ tag: String) -> some View {
        TextField("Tag", text: $editText)
            .textFieldStyle(.plain)
            .font(.caption.weight(.medium))
            .focused($focus, equals: .edit)
            .frame(width: max(70, min(220, CGFloat(editText.count) * 7 + 16)))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(DesignTokens.Palette.surface))
            .overlay(Capsule().stroke(DesignTokens.Palette.accent.opacity(0.8), lineWidth: 1))
            .onSubmit { finishEditing(tag, save: true) }
            .onExitCommand { finishEditing(tag, save: false) }
            .onChange(of: focus) { _, new in
                // Clicking elsewhere keeps the change, like any text field.
                if new != .edit, editingTag == tag { finishEditing(tag, save: true) }
            }
            .help("Return to save, Esc to cancel. Empty removes the tag.")
            .accessibilityLabel("Rename tag \(tag)")
    }

    private func startEditing(_ tag: String) {
        editText = tag
        editingTag = tag
        focus = .edit
    }

    private func finishEditing(_ tag: String, save: Bool) {
        guard editingTag == tag else { return }
        editingTag = nil
        if save, editText != tag { onRename(tag, editText) }
    }

    // MARK: - Add

    private var addField: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            TextField(tags.isEmpty ? "Add a tag" : "Add tag", text: $newTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .focused($focus, equals: .add)
                .frame(width: 110)
                .onSubmit(add)
                .onChange(of: focus) { old, new in
                    if old == .add, new != .add { add() }
                }
                .accessibilityIdentifier("task-tags-add")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(DesignTokens.Palette.surface))
        .overlay(
            Capsule().stroke(
                focus == .add ? DesignTokens.Palette.accent.opacity(0.7) : DesignTokens.Palette.hairline,
                style: StrokeStyle(lineWidth: 1, dash: focus == .add ? [] : [3, 2])
            )
        )
        .help("Type a tag and press Return. Separate several with commas.")
    }

    private func add() {
        let value = newTag
        newTag = ""
        guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onAdd(value)
    }

    private func suggestionRow(_ matches: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(newTag.isEmpty ? "Used before:" : "Matching:")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .padding(.top, 3)
            ChipFlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(matches, id: \.self) { tag in
                    Button {
                        newTag = ""
                        onAdd(tag)
                        focus = .add
                    } label: {
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(DesignTokens.Palette.surfaceRaised))
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .help("Add “\(tag)”")
                }
            }
        }
        .transition(.opacity)
    }
}
