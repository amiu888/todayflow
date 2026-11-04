import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The Jira-style task detail window (driver.md FR-20, FR-21, FR-22):
/// breadcrumb, editable title, status / priority pills, dates with shortcuts,
/// markdown description, subtasks, attachments, links, and the action row.
///
/// Pure presentation — all logic lives in `DetailViewModel`. FR-23's
/// AppKit-heavy parts (Quick Look, Reveal in Finder, live markdown rendering)
/// belong to the 6 Mac app layer, which swaps them in around this view.
public struct DetailView: View {
    public let model: DetailViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?

    /// The two focusable text fields.
    private enum Field: Hashable {
        case title
        case description
    }

    private var motion: Motion {
        Motion(preference: reduceMotion ? .reduced : .full)
    }

    public init(model: DetailViewModel) {
        self.model = model
    }

    /// Convenience for hosts that only know the item id and their
    /// repositories (the 6 Mac app layer uses this).
    @MainActor
    public init(
        itemId: UUIDv7,
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        onClosed: (@MainActor () -> Void)? = nil
    ) {
        self.model = DetailViewModel(
            itemId: itemId,
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            onClosed: onClosed
        )
    }

    // MARK: Body

    @MainActor
    public var body: some View {
        Group {
            if model.item != nil {
                content
            } else if model.isDeleted {
                // The host closes the window via `onClosed`; show nothing
                // for the brief moment before it does.
                Color.clear
            } else {
                loadingState
            }
        }
        .frame(width: DesignTokens.Window.detail.width, height: DesignTokens.Window.detail.height)
        .task { await model.load() }
        .onChange(of: focusedField) { old, _ in
            // FR-22: inline edits commit on interaction — here, on focus loss.
            if old == .description {
                Task { await model.commit() }
            }
        }
    }

    // MARK: Content

    @MainActor
    @ViewBuilder
    private var content: some View {
        if let item = model.item {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap * 2) {
                    breadcrumb(item)
                    titleField
                    pillsRow(item)
                    datesRow
                    descriptionSection

                    if !model.children.isEmpty {
                        childrenSection
                    }
                    if !model.attachments.isEmpty {
                        attachmentsSection
                    }

                    linksSection

                    if let error = model.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    actionsRow
                }
                .padding(20)
            }
        }
    }

    // MARK: Sections

    @MainActor
    @ViewBuilder
    private func breadcrumb(_ item: WorkItem) -> some View {
        if let parent = model.parent {
            HStack(spacing: 6) {
                Text(parent.title)
                Text("›")
                Text(item.kind.label)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private var titleField: some View {
        @Bindable var model = model

        return TextField("Title", text: $model.edit.title)
            .font(.title2.weight(.semibold))
            .textFieldStyle(.plain)
            .focused($focusedField, equals: .title)
            .onSubmit {
                Task { await model.commit() }
            }
    }

    @MainActor
    private func pillsRow(_ item: WorkItem) -> some View {
        HStack(spacing: 8) {
            statusPill
            priorityPill

            Text(item.kind.label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius)
                        .fill(.quaternary.opacity(0.5))
                )

            if let tags = model.item?.tags, !tags.isEmpty {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.quaternary.opacity(0.4)))
                }
            }

            // FR-20: the roll-up ring is always visible on containers.
            if item.kind == .project || item.kind == .epic {
                let ring = ProgressRingModel(result: model.progress)
                ProgressRingView(model: ring, motion: motion)
                Text(ring.doneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private var statusPill: some View {
        Menu {
            ForEach(Status.allCases.filter { $0 != .blocked }, id: \.self) { status in
                Button {
                    Task { await model.setStatus(status) }
                } label: {
                    Label(status.label, systemImage: status.symbolName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.displayStatus.symbolName)
                Text(model.displayStatus.label)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(statusTint(model.displayStatus).opacity(0.15))
            )
            .foregroundStyle(statusTint(model.displayStatus))
        }
        .disabled(model.isSaving)
    }

    @MainActor
    private var priorityPill: some View {
        Menu {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button {
                    Task { await model.setPriority(priority) }
                } label: {
                    HStack {
                        Label(priority.label, systemImage: priority.symbolName)
                        if priority == model.priority {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                PriorityDotView(priority: model.priority, size: 8)
                Text(model.priority.label)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary.opacity(0.4)))
        }
        .disabled(model.isSaving)
    }

    @MainActor
    private var datesRow: some View {
        @Bindable var model = model

        return HStack(spacing: 12) {
            DatePicker(
                "Starts",
                selection: $model.edit.startAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .onChange(of: model.edit.startAt) {
                Task { await model.commit() }
            }

            DatePicker(
                "Due",
                selection: $model.edit.endAt,
                displayedComponents: [.date, .hourAndMinute]
            )
            .onChange(of: model.edit.endAt) {
                Task { await model.commit() }
            }

            // FR-22 compact date shortcuts.
            Menu {
                ForEach(DetailViewModel.DateShortcut.allCases) { shortcut in
                    Button(shortcut.label) {
                        Task { await model.applyDateShortcut(shortcut) }
                    }
                }
            } label: {
                Label("Set due", systemImage: "calendar")
            }
        }
        .font(.callout)
        .disabled(model.isSaving)
    }

    @MainActor
    private var descriptionSection: some View {
        @Bindable var model = model

        return TextEditor(text: $model.edit.descriptionMd)
            .font(.body)
            .frame(minHeight: 100, maxHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius)
                    .fill(.quaternary.opacity(0.5))
            )
            .focused($focusedField, equals: .description)
    }

    @MainActor
    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
            Text(childrenTitle)
                .font(.headline)

            ForEach(model.children) { child in
                HStack(spacing: 8) {
                    Image(systemName: child.status.symbolName)
                        .foregroundStyle(statusTint(child.status))
                    Text(child.title)
                        .strikethrough(child.status.isComplete)
                        .foregroundStyle(
                            child.status.isComplete ? .secondary : .primary
                        )
                    Spacer()
                    PriorityDotView(priority: child.priority, size: 8)
                }
                .frame(height: DesignTokens.Spacing.rowHeight)
            }
        }
    }

    @MainActor
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
            Text("Attachments")
                .font(.headline)

            ForEach(model.attachments) { attachment in
                HStack(spacing: 8) {
                    AttachmentIconView(attachment: attachment, size: 14)
                    Text(attachment.displayName)
                    Spacer()
                    Button {
                        Task { await model.removeAttachment(attachment.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isSaving)
                }
                .frame(height: DesignTokens.Spacing.rowHeight)
            }
        }
    }

    @MainActor
    @ViewBuilder
    private var linksSection: some View {
        // FR-20: links are display-only in 5c; adding and removing them
        // comes with 5d Hierarchy / 6 Mac.
        if !model.blockers.isEmpty {
            linkGroup("Blocked by", items: model.blockers)
        }
        if !model.blockings.isEmpty {
            linkGroup("Blocks", items: model.blockings)
        }
        if !model.related.isEmpty {
            linkGroup("Related", items: model.related)
        }
    }

    @MainActor
    private func linkGroup(_ title: String, items: [WorkItem]) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
            Text(title)
                .font(.headline)

            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.status.symbolName)
                        .foregroundStyle(statusTint(item.status))
                    Text(item.title)
                        .strikethrough(item.status.isComplete)
                        .foregroundStyle(
                            item.status.isComplete ? .secondary : .primary
                        )
                    Spacer()
                }
                .frame(height: DesignTokens.Spacing.rowHeight)
            }
        }
    }

    @MainActor
    private var actionsRow: some View {
        HStack(spacing: 12) {
            if model.item?.status.isComplete == true {
                Button("Reopen") {
                    Task { await model.setStatus(.todo) }
                }
            } else {
                Button {
                    Task { await model.complete() }
                } label: {
                    Label("Complete", systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            }

            Button("Move to tomorrow") {
                Task { await model.moveToTomorrow() }
            }

            Spacer()

            Button(role: .destructive) {
                Task { await model.delete() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .disabled(model.isSaving)
    }

    // MARK: Loading / missing

    @MainActor
    private var loadingState: some View {
        VStack(spacing: 12) {
            if let error = model.lastError {
                Text(error)
                    .foregroundStyle(.red)
            } else if model.isLoading {
                ProgressView()
            } else {
                Text("This item is no longer available.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers

    @MainActor
    private func statusTint(_ status: Status) -> Color {
        switch status {
        case .todo: return .gray
        case .inProgress: return .blue
        case .blocked: return .red
        case .done: return .green
        case .cancelled: return .gray
        }
    }

    @MainActor
    private var childrenTitle: String {
        switch model.item?.kind ?? .task {
        case .epic: return "Projects"
        case .project: return "Tasks"
        case .task, .subtask: return "Subtasks"
        }
    }
}

// MARK: - Preview

private struct DetailPreviewHost: View {
    @State private var model: DetailViewModel?

    var body: some View {
        Group {
            if let model {
                DetailView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let repository = InMemoryWorkItemRepository()
            let linkRepository = InMemoryLinkRepository()
            let attachmentRepository = InMemoryAttachmentRepository()

            let project = WorkItem(kind: .project, title: "Website")
            let task = WorkItem(
                kind: .task,
                title: "Review contract",
                parentId: project.id,
                descriptionMd: "## Scope\n\nCheck the **scope** section carefully.",
                status: .inProgress,
                priority: .high
            )
            let subtask = WorkItem(
                kind: .subtask,
                title: "Check scope",
                parentId: task.id,
                status: .done,
                completedAt: .now
            )
            let prerequisite = WorkItem(kind: .task, title: "Sign NDA")

            await repository.seed(project)
            await repository.seed(task)
            await repository.seed(subtask)
            await repository.seed(prerequisite)
            await linkRepository.seed(
                ItemLink(fromId: prerequisite.id, toId: task.id)
            )
            await attachmentRepository.seed(
                Attachment(itemId: task.id, kind: .file, displayName: "contract.pdf")
            )

            model = DetailViewModel(
                itemId: task.id,
                repository: repository,
                linkRepository: linkRepository,
                attachmentRepository: attachmentRepository
            )
        }
    }
}

#Preview {
    DetailPreviewHost()
}
