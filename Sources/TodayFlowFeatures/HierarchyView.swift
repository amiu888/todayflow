import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// The hierarchy window (driver.md FR-16, MVP gate line 515): the full
/// epics → projects → tasks → subtasks tree with progress roll-up,
/// drag-to-reparent, and context-menu actions.
public struct HierarchyView: View {
    public let model: HierarchyViewModel

    public init(model: HierarchyViewModel) {
        self.model = model
    }

    /// Convenience for hosts that only know their repositories (the 6 Mac
    /// app layer uses this).
    @MainActor
    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        onOpenDetail: (@MainActor (UUIDv7) -> Void)? = nil
    ) {
        let model = HierarchyViewModel(
            repository: repository,
            linkRepository: linkRepository,
            calendar: calendar,
            deviceId: deviceId
        )
        model.onOpenDetail = onOpenDetail
        self.model = model
    }

    @MainActor
    public var body: some View {
        Group {
            if model.lastError != nil {
                errorNote
            }
            if model.nodes.isEmpty && !model.isLoading {
                Text("Nothing here yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.nodes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tree
            }
        }
        .frame(width: DesignTokens.Window.hierarchy.width, height: DesignTokens.Window.hierarchy.height)
        .background { keyboardShortcuts }
        .task { await model.refresh() }
    }

    // MARK: - Keyboard (driver.md FR-12)

    /// ⌥↑ / ⌥↓ move the selected row among its siblings.
    @MainActor
    private var keyboardShortcuts: some View {
        Group {
            Button("Move up") {
                guard let id = model.selectedId else { return }
                Task { @MainActor in await model.moveUp(id) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.option])

            Button("Move down") {
                guard let id = model.selectedId else { return }
                Task { @MainActor in await model.moveDown(id) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.option])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var tree: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.sectionGap) {
                ForEach(model.visibleRows) { row in
                    HierarchyRowView(row: row, model: model)
                        .padding(.leading, CGFloat(row.depth) * 20)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var errorNote: some View {
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }
}

// MARK: - Row

private struct HierarchyRowView: View {
    let row: VisibleRow
    let model: HierarchyViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            if row.node.children.isEmpty {
                Spacer().frame(width: 16)
            } else {
                Button {
                    model.toggle(row.node.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .rotationEffect(.degrees(model.expanded.contains(row.node.id) ? 90 : 0))
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: Self.kindSymbol(row.node.item.kind))
                .foregroundStyle(.secondary)

            Text(row.node.item.title)
                .strikethrough(row.node.item.status == .done)
                .lineLimit(1)
                .foregroundStyle(row.node.item.status == .cancelled ? Color.secondary : Color.primary)

            if !row.node.item.tags.isEmpty {
                Text(TagName.display(row.node.item.tags, limit: 2))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(DesignTokens.Palette.accent)
                    .lineLimit(1)
                    .help(row.node.item.tags.map { "#\($0)" }.joined(separator: ", "))
            }

            PriorityDotView(priority: row.node.item.priority)

            switch row.node.item.kind {
            case .epic, .project:
                ProgressRingView(
                    model: ProgressRingModel(result: row.node.progress),
                    motion: Motion(preference: reduceMotion ? .reduced : .full)
                )
                Text(ProgressRingModel(result: row.node.progress).doneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .task, .subtask:
                Image(systemName: row.node.item.status.symbolName)
                    .foregroundStyle(row.node.item.status == .done ? Color.green : Color.secondary)
            }

            Spacer()

            Text(row.node.item.endAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: DesignTokens.Spacing.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if model.selectedId == row.node.id {
                RoundedRectangle(
                    cornerRadius: DesignTokens.Spacing.cornerRadius,
                    style: .continuous
                )
                .fill(Color.accentColor.opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.select(row.node.id)
        }
        .onTapGesture(count: 2) {
            model.onOpenDetail?(row.node.id)
        }
        .draggable(WorkItemDragPayload(itemId: row.node.id)) {
            Text(row.node.item.title)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: WorkItemDragPayload.self) { payloads, _ in
            guard let payload = payloads.first else { return false }
            Task { @MainActor in
                await model.reparent(payload.itemId, toParent: row.node.id)
            }
            return true
        } isTargeted: { targeting in
            isTargeted = targeting
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
        .contextMenu {
            Button("Open details") {
                model.onOpenDetail?(row.node.id)
            }
            Divider()

            // driver.md §2: epic → project, project → task, task → subtask.
            if row.node.item.kind == .epic {
                Button("Add project") {
                    Task { @MainActor in
                        await model.addChild(to: row.node.id, kind: .project, title: "New Project")
                    }
                }
            } else if row.node.item.kind == .project {
                Button("Add task") {
                    Task { @MainActor in
                        await model.addChild(to: row.node.id, kind: .task, title: "New Task")
                    }
                }
            } else if row.node.item.kind == .task {
                Button("Add subtask") {
                    Task { @MainActor in
                        await model.addChild(to: row.node.id, kind: .subtask, title: "New Subtask")
                    }
                }
            }

            // FR-12: the same moves are available on ⌥↑/⌥↓ for the selection.
            Button("Move up") {
                Task { @MainActor in await model.moveUp(row.node.id) }
            }
            Button("Move down") {
                Task { @MainActor in await model.moveDown(row.node.id) }
            }

            if row.node.item.parentId != nil {
                Button("Move to top level") {
                    Task { @MainActor in await model.moveToTopLevel(row.node.id) }
                }
            }

            if row.node.item.kind == .task || row.node.item.kind == .subtask {
                Button("Complete") {
                    Task { @MainActor in await model.complete(row.node.id) }
                }
            }

            if row.node.children.isEmpty {
                Button("Delete", role: .destructive) {
                    Task { @MainActor in await model.delete(row.node.id) }
                }
            } else {
                Button("Delete (keep children)", role: .destructive) {
                    Task { @MainActor in await model.delete(row.node.id) }
                }
                Button("Delete with children", role: .destructive) {
                    Task { @MainActor in await model.delete(row.node.id, withChildren: true) }
                }
            }
        }
    }

    private static func kindSymbol(_ kind: WorkItem.Kind) -> String {
        switch kind {
        case .epic: return "flag.fill"
        case .project: return "folder.fill"
        case .task: return "checklist"
        case .subtask: return "circle.dashed"
        }
    }
}

// MARK: - Preview

private struct HierarchyPreviewHost: View {
    @State private var model: HierarchyViewModel?

    var body: some View {
        Group {
            if let model {
                HierarchyView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let repository = InMemoryWorkItemRepository()
            let linkRepository = InMemoryLinkRepository()

            let epic = WorkItem(kind: .epic, title: "Launch v2", displayOrder: "a")
            let design = WorkItem(kind: .project, title: "Design", parentId: epic.id, displayOrder: "b")
            let backend = WorkItem(kind: .project, title: "Backend", parentId: epic.id, displayOrder: "c")
            let wireframes = WorkItem(
                kind: .task, title: "Wireframes", parentId: design.id,
                status: .done, completedAt: .now, displayOrder: "d"
            )
            let tokens = WorkItem(
                kind: .task, title: "Design tokens", parentId: design.id,
                priority: .high, displayOrder: "e"
            )
            let api = WorkItem(
                kind: .task, title: "API contract", parentId: backend.id,
                status: .inProgress, displayOrder: "f"
            )
            let mock = WorkItem(
                kind: .subtask, title: "Mock endpoints", parentId: api.id,
                status: .done, completedAt: .now, displayOrder: "g"
            )
            let standalone = WorkItem(title: "Dentist appointment", displayOrder: "h")

            for item in [epic, design, backend, wireframes, tokens, api, mock, standalone] {
                await repository.seed(item)
            }

            model = HierarchyViewModel(
                repository: repository,
                linkRepository: linkRepository
            )
        }
    }
}

#Preview {
    HierarchyPreviewHost()
}
