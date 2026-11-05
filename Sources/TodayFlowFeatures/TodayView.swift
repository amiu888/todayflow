import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign
#if canImport(AppKit)
import AppKit
#endif

/// The Today panel: progress header, filter chips, optional search row,
/// and the task list (overdue / today / done sections).
///
/// The container is pure presentation: it renders `TodayViewModel` state
/// and forwards user intent back to it. All business logic lives in the
/// view model.
public struct TodayView: View {
    private let model: TodayViewModel
    #if canImport(AppKit)
    /// Handles a drop/paste; the second argument is the target task when the
    /// drop landed on a row (FR-04), or `nil` for the panel background (FR-01).
    private let onDrop: (@MainActor ([NSItemProvider], UUIDv7?) -> Bool)?
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @State private var isPanelDropTargeted: Bool = false
    @State private var dropTargetId: UUIDv7?
    @State private var showsUndoBar = false
    @State private var undoBarTask: Task<Void, Never>?

    public init(model: TodayViewModel) {
        self.model = model
        #if canImport(AppKit)
        self.onDrop = nil
        #endif
    }

    /// Convenience initializer for hosts that own the repositories.
    ///
    /// `onDrop` is optional so previews and tests can build the panel without
    /// an AppKit drop receiver; the production host supplies it.
    @MainActor
    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        settingRepository: (any SettingRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil,
        onDrop: (@MainActor ([NSItemProvider], UUIDv7?) -> Bool)? = nil
    ) {
        self.model = TodayViewModel(
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            settingRepository: settingRepository,
            calendar: calendar,
            deviceId: deviceId,
            onOpenTask: onOpenTask
        )
        #if canImport(AppKit)
        self.onDrop = onDrop
        #endif
    }

    private var motion: Motion {
        Motion(preference: reduceMotion ? .reduced : .full)
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            ProgressHeaderView(progress: model.progress, motion: motion)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            FilterChipsView(
                filter: model.filter,
                sort: model.sort,
                projects: model.projects,
                projectFilter: model.projectFilter,
                onFilterChange: { filter in
                    Task { @MainActor in
                        model.filter = filter
                    }
                },
                onSortChange: { sort in
                    Task { @MainActor in
                        await model.setSort(sort)
                    }
                },
                onProjectChange: { projectId in
                    Task { @MainActor in
                        model.projectFilter = projectId
                    }
                },
                onSearch: {
                    Task { @MainActor in
                        isSearching = true
                    }
                }
            )

            if isSearching {
                searchField
            }

            if let lastError = model.lastError {
                errorBanner(lastError)
            }

            if model.isLoading && model.visibleRows.isEmpty && model.visibleDoneRows.isEmpty {
                loadingState
            } else {
                list
            }
        }
        .frame(
            minWidth: DesignTokens.Window.panelMinimum.width,
            minHeight: DesignTokens.Window.panelMinimum.height
        )
        .background { keyboardShortcuts }
        #if canImport(AppKit)
        .onDrop(of: CaptureDropTypes.supported, isTargeted: $isPanelDropTargeted) { providers in
            onDrop?(providers, nil) ?? false
        }
        // FR-06: ⌘V behaves like a drop of the clipboard. The focused text
        // field consumes its own paste first, so typing is never hijacked.
        .onPasteCommand(of: CaptureDropTypes.supported) { providers in
            guard !isSearching else { return }
            _ = onDrop?(providers, nil)
        }
        .overlay { panelDropIndicator }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.attachmentsChanged)) { _ in
            Task { @MainActor in
                await model.load()
            }
        }
        .onChange(of: model.completionUndo) { _, undo in
            undoBarTask?.cancel()
            guard let undo else {
                showsUndoBar = false
                return
            }
            showsUndoBar = true
            undoBarTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, model.completionUndo == undo else { return }
                showsUndoBar = false
            }
        }
        .overlay(alignment: .bottom) { undoBar }
        .task { await model.observe() }
    }

    /// The short-lived "Completed · Undo" bar (FR-14).
    @MainActor
    @ViewBuilder
    private var undoBar: some View {
        if showsUndoBar, model.completionUndo != nil {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "#0ca30c"))
                Text("Task completed")
                    .font(.caption)
                Spacer()
                Button("Undo") {
                    showsUndoBar = false
                    Task { @MainActor in await model.undoComplete() }
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.08)))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    #if canImport(AppKit)
    /// A thin accent border while a drag hovers anywhere over the panel.
    @MainActor
    @ViewBuilder
    private var panelDropIndicator: some View {
        if isPanelDropTargeted {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(3)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Per-row targeting state, so only the hovered row highlights (FR-04).
    private func dropBinding(for id: UUIDv7) -> Binding<Bool> {
        Binding(
            get: { dropTargetId == id },
            set: { targeted in
                if targeted {
                    dropTargetId = id
                } else if dropTargetId == id {
                    dropTargetId = nil
                }
            }
        )
    }
    #endif

    // MARK: - Keyboard (driver.md FR-12)

    /// ⌥↑ / ⌥↓ move the selected row (FR-12). Zero-sized buttons register the
    /// shortcuts for the window without taking any layout space.
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

            Button("Undo complete") {
                Task { @MainActor in await model.undoComplete() }
            }
            .keyboardShortcut("z", modifiers: .command)

            if !isSearching {
                Button("Complete selected") {
                    guard let id = model.selectedId else { return }
                    Task { @MainActor in await model.toggle(id) }
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Open selected") {
                    guard let id = model.selectedId else { return }
                    Task { @MainActor in await model.quickAction(id, .open) }
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Search

    @MainActor
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { isSearching = false }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: searchText) { _, newValue in
            model.searchText = newValue
        }
    }

    // MARK: - List

    @MainActor
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
                if !model.visibleOverdueRows.isEmpty {
                    sectionHeader("Overdue", count: model.visibleOverdueRows.count, tint: Color(hex: "#d03b3b"))

                    ForEach(model.visibleOverdueRows) { row in
                        rowView(row)
                    }
                }

                if !model.visibleOpenRows.isEmpty {
                    sectionHeader("Today", count: model.visibleOpenRows.count, tint: .primary)

                    ForEach(model.visibleOpenRows) { row in
                        rowView(row)
                    }
                }

                if !model.visibleDoneRows.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 0) {
                            ForEach(model.visibleDoneRows) { row in
                                rowView(row)
                            }
                        }
                    } label: {
                        sectionHeader("Done today", count: model.visibleDoneRows.count, tint: .secondary)
                    }
                }

                if model.visibleRows.isEmpty && model.visibleDoneRows.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @MainActor
    private func rowView(_ row: TaskRowModel) -> some View {
        let content = TaskRowView(
            model: row,
            onToggle: { id in
                Task { @MainActor in
                    await model.toggle(id)
                }
            },
            onQuickAction: { id, action in
                Task { @MainActor in
                    await model.quickAction(id, action)
                }
            },
            motion: motion,
            isSelected: model.selectedId == row.id,
            onSelect: { id in
                Task { @MainActor in
                    model.select(id)
                }
            },
            onMove: { draggedId, targetId, before in
                Task { @MainActor in
                    await model.move(draggedId, targetId: targetId, before: before)
                }
            }
        )

        #if canImport(AppKit)
        return content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(dropTargetId == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            .onDrop(
                of: CaptureDropTypes.supported,
                isTargeted: dropBinding(for: row.id)
            ) { providers in
                // FR-04: a drop on a row adds attachments to that task.
                onDrop?(providers, row.id) ?? false
            }
        #else
        return content
        #endif
    }

    @MainActor
    private func sectionHeader(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - States

    @MainActor
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#fab219"))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(hex: "#fab219").opacity(0.12))
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView()

            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.body.weight(.medium))

            Text(emptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private var emptyTitle: String {
        if model.progress.total == 0 {
            return "Nothing scheduled"
        } else if model.progress.isCleared {
            return "Day cleared"
        } else {
            return "No matching tasks"
        }
    }

    @MainActor
    private var emptySubtitle: String {
        if model.progress.total == 0 {
            return "Drop something anywhere, or press ⌃⌥Space to add a task."
        } else if model.progress.isCleared {
            return "Everything on today's list is done."
        } else {
            return "Try a different filter or search."
        }
    }
}

#Preview {
    TodayView(
        repository: InMemoryWorkItemRepository(),
        linkRepository: InMemoryLinkRepository(),
        attachmentRepository: InMemoryAttachmentRepository()
    )
    .frame(width: DesignTokens.Window.panel.width, height: DesignTokens.Window.panel.height)
}
