import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// The Today panel: progress header, filter chips, optional search row,
/// and the task list (overdue / today / done sections).
///
/// The container is pure presentation: it renders `TodayViewModel` state
/// and forwards user intent back to it. All business logic lives in the
/// view model.
public struct TodayView: View {
    private let model: TodayViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""

    public init(model: TodayViewModel) {
        self.model = model
    }

    /// Convenience initializer for hosts that own the repositories.
    @MainActor
    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        settingRepository: (any SettingRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil
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
        .task { await model.observe() }
    }

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
        TaskRowView(
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
