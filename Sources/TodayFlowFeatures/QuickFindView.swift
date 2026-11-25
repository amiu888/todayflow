import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The Quick Find panel (⌘K): a big search field, filter chips, and the
/// best matches with why they matched. Keyboard first: ↑↓ ↩ ⌘↩ ⌥↩ esc.
public struct QuickFindView: View {
    @Bindable var model: QuickFindModel
    @FocusState private var fieldFocused: Bool

    public init(model: QuickFindModel) {
        self.model = model
    }

    private static let filterHints: [(label: String, token: String, help: String)] = [
        ("#tag", "#", "Tasks with a tag"),
        ("@person", "@", "Tasks linked to a contact"),
        ("/project", "/", "Tasks in a project"),
        ("due:today", "due:today", "Due today"),
        ("due:week", "due:week", "Due in the next 7 days"),
        ("overdue", "overdue", "Open and past due"),
        ("done", "done", "Finished tasks only"),
    ]

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            if !model.completions.isEmpty {
                completionRow
            } else if model.text.isEmpty {
                hintRow
            }
            Divider()
            resultsList
            Divider()
            footer
        }
        .frame(minWidth: 520, idealWidth: 640, maxWidth: .infinity, minHeight: 360, idealHeight: 460, maxHeight: .infinity)
        .background(DesignTokens.Palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.Palette.hairline)
        )
        .onAppear { fieldFocused = true }
        .onEscape { model.onClose?() }
        .accessibilityIdentifier("quick-find")
    }

    // MARK: - Field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            TextField("Find a task: words, a ticket number, #tag, @person, /project", text: $model.text)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.tab) {
                    guard let first = model.completions.first else { return .ignored }
                    model.complete(first)
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        Task { await model.completeSelected() }
                    } else if press.modifiers.contains(.option) {
                        Task { await model.doTodaySelected() }
                    } else if let first = model.completions.first {
                        model.complete(first)
                    } else {
                        model.activate()
                    }
                    return .handled
                }
                .accessibilityIdentifier("quick-find-field")
            if model.isLoading {
                ProgressView().controlSize(.small)
            } else if !model.text.isEmpty {
                Button {
                    model.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var hintRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Filter:")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                ForEach(Self.filterHints, id: \.token) { hint in
                    Button {
                        if hint.token.count == 1 {
                            model.text += (model.text.isEmpty || model.text.hasSuffix(" ") ? "" : " ") + hint.token
                        } else {
                            model.insertFilter(hint.token)
                        }
                        fieldFocused = true
                    } label: {
                        Text(hint.label).font(.caption.monospaced())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(hint.help)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var completionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Tab:")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                ForEach(model.completions) { completion in
                    Button {
                        model.complete(completion)
                        fieldFocused = true
                    } label: {
                        Text(completion.label).font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text(model.heading.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    if model.results.isEmpty {
                        emptyState
                    }
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                        row(result, selected: index == model.selection)
                            .id(index)
                            .onTapGesture(count: 2) { model.open(result.id) }
                            .onTapGesture { model.selection = index }
                    }
                    if model.showsAskRow {
                        askRow(selected: model.selection == model.results.count)
                            .id(model.results.count)
                            .onTapGesture { model.ask() }
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: model.selection) { _, new in
                withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new) }
            }
        }
    }

    private var emptyState: some View {
        Text(model.query.isEmpty
            ? "Tasks you open show up here. Start typing to search everything."
            : "No task matches. Try fewer words, or ask AI below.")
            .font(.callout)
            .foregroundStyle(DesignTokens.Palette.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private func row(_ result: QuickFindResult, selected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(result.projectColor.flatMap { Color(hex: $0) } ?? DesignTokens.Palette.textSecondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if result.item.status.isTerminal {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text(result.item.title)
                        .font(.body.weight(.medium))
                        .strikethrough(result.item.status.isTerminal, color: DesignTokens.Palette.textSecondary)
                        .lineLimit(1)
                    if result.isRecent && model.query.isEmpty {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                            .help("Opened recently")
                    }
                }
                Text(detailLine(result))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .lineLimit(1)
                if let snippet = result.snippet, let reason = result.reason {
                    (Text("\(reason): ").fontWeight(.semibold) + Text(snippet))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? DesignTokens.Palette.accent.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func detailLine(_ result: QuickFindResult) -> String {
        var parts: [String] = []
        if let project = result.projectTitle { parts.append(project) }
        let item = result.item
        if item.status.isTerminal {
            parts.append("Done \((item.completedAt ?? item.updatedAt).formatted(.relative(presentation: .named)))")
        } else if item.endAt < .now {
            parts.append("Overdue · was due \(item.endAt.formatted(.relative(presentation: .named)))")
        } else {
            parts.append("Due \(item.endAt.formatted(.relative(presentation: .named)))")
        }
        if !item.tags.isEmpty { parts.append(TagName.display(item.tags, limit: 3)) }
        return parts.joined(separator: " · ")
    }

    private func askRow(selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(DesignTokens.Palette.accent)
            Text("Ask AI: “\(model.text.trimmingCharacters(in: .whitespaces))”")
                .font(.body)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? DesignTokens.Palette.accent.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6)
        .help("Can’t find it? Describe it and the AI looks through your tasks")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let flash = model.flash {
                Label(flash, systemImage: "checkmark.circle")
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .lineLimit(1)
            } else {
                keyHint("↩", "Open")
                keyHint("⌘↩", "Done")
                keyHint("⌥↩", "Do today")
                keyHint("↑↓", "Move")
            }
            Spacer()
            keyHint("esc", "Close")
        }
        .font(.caption)
        .foregroundStyle(DesignTokens.Palette.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(DesignTokens.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}
