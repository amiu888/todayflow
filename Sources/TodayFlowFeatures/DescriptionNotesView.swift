import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The task description as notes, newest first, each with its time on the
/// left. "Hide times" folds the time column away (remembered per Mac).
struct DescriptionNotesView: View {
    let notes: [DescriptionLog.Note]
    let onAdd: @MainActor (String) -> Void
    let onUpdate: @MainActor (String, String) -> Void
    let onDelete: @MainActor (String) -> Void
    var now: Date = .now

    @AppStorage("todayflow.notes.showTimes") private var showTimes = true
    @State private var newText = ""
    @State private var editingId: String?
    @State private var editText = ""
    @State private var hoveredId: String?
    @FocusState private var composerFocused: Bool

    private let timeWidth: CGFloat = 78

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            composer
            if notes.isEmpty {
                Text("No notes yet. What happened, what was decided, what's next.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        noteRow(note, isLast: index == notes.count - 1)
                    }
                }
            }
        }
        .accessibilityIdentifier("task-notes")
    }

    // MARK: - Header and composer

    private var header: some View {
        HStack(spacing: 6) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            if !notes.isEmpty {
                Text("\(notes.count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DesignTokens.Palette.surfaceRaised, in: Capsule())
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showTimes.toggle() }
            } label: {
                Label(showTimes ? "Hide times" : "Show times", systemImage: showTimes ? "clock.fill" : "clock")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(showTimes ? "Hide the time next to each note" : "Show when each note was added")
            .accessibilityIdentifier("task-notes-times")
        }
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if newText.isEmpty {
                    Text("Add a note…")
                        .font(.body)
                        .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.8))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $newText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($composerFocused)
                    .frame(minHeight: 40, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("New note")
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius, style: .continuous)
                    .fill(DesignTokens.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius, style: .continuous)
                    .stroke(composerFocused ? DesignTokens.Palette.accent.opacity(0.7) : DesignTokens.Palette.hairline)
            )
            if composerFocused || !newText.isEmpty {
                HStack(spacing: 8) {
                    AIRewriteButton(text: newText, field: "New note", applyTitle: "Use This") { text in
                        newText = text
                        composerFocused = true
                    }
                    Spacer()
                    Text("⌘↩ to add")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    Button("Add Note", action: add)
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("task-notes-add")
                }
            }
        }
    }

    private func add() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newText = ""
        onAdd(text)
    }

    // MARK: - Rows

    private func noteRow(_ note: DescriptionLog.Note, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if showTimes {
                timeColumn(note)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            timeline(isLast: isLast)
            VStack(alignment: .leading, spacing: 6) {
                if editingId == note.id {
                    editor(note)
                } else {
                    Text(LocalizedStringKey(note.text))
                        .font(.body)
                        .lineSpacing(3)
                        .foregroundStyle(DesignTokens.Palette.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
            if editingId != note.id {
                rowActions(note)
                    .opacity(hoveredId == note.id ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveredId = $0 ? note.id : (hoveredId == note.id ? nil : hoveredId) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Note, \(note.date.formatted(date: .abbreviated, time: .shortened))")
    }

    private func timeColumn(_ note: DescriptionLog.Note) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(dayText(note.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.textPrimary)
            Text(note.isUndated ? "first note" : note.date.formatted(date: .omitted, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .frame(width: timeWidth, alignment: .trailing)
        .padding(.top, 2)
        .help(note.isUndated
            ? "Written before notes had times; shown with the day the task was created"
            : note.date.formatted(date: .complete, time: .standard))
    }

    private func timeline(isLast: Bool) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(DesignTokens.Palette.accent)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            if !isLast {
                Rectangle()
                    .fill(DesignTokens.Palette.hairline)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 3)
            }
        }
        .frame(width: 7)
    }

    private func rowActions(_ note: DescriptionLog.Note) -> some View {
        HStack(spacing: 2) {
            AIRewriteButton(text: note.text, field: "Note", compact: true) { text in
                onUpdate(note.id, text)
            }
            Button {
                editText = note.text
                editingId = note.id
            } label: {
                Image(systemName: "pencil")
            }
            .help("Edit this note (it keeps its time)")
            Button {
                onDelete(note.id)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete this note")
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .foregroundStyle(DesignTokens.Palette.textSecondary)
    }

    private func editor(_ note: DescriptionLog.Note) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextEditor(text: $editText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.Palette.accent.opacity(0.7))
                )
            HStack(spacing: 8) {
                AIRewriteButton(text: editText, field: "Note", applyTitle: "Use This") { text in
                    editText = text
                }
                Spacer()
                Button("Cancel") { editingId = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let text = editText
                    editingId = nil
                    onUpdate(note.id, text)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }

    private func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
