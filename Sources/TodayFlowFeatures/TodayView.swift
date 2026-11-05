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
    private let onOpenUpcoming: (@MainActor () -> Void)?
    private let onShowMiniCalendar: (@MainActor () -> Void)?
    private let onOpenTray: (@MainActor (UUIDv7) -> Void)?
    private let windowActions: WindowMenuActions?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @State private var isPanelDropTargeted: Bool = false
    @State private var dropTargetId: UUIDv7?
    @State private var showsUndoBar = false
    @State private var undoBarTask: Task<Void, Never>?
    @State private var captureConfirmation: String?
    @State private var captureToastTask: Task<Void, Never>?

    public init(model: TodayViewModel) {
        self.model = model
        #if canImport(AppKit)
        self.onDrop = nil
        #endif
        self.onOpenUpcoming = nil
        self.onShowMiniCalendar = nil
        self.onOpenTray = nil
        self.windowActions = nil
    }

    /// Host initializer used when the window manager owns the shared model.
    @MainActor
    public init(
        model: TodayViewModel,
        onOpenTask: (@MainActor (UUIDv7) -> Void)? = nil,
        onFocusTask: (@MainActor (UUIDv7) -> Void)? = nil,
        onDrop: (@MainActor ([NSItemProvider], UUIDv7?) -> Bool)? = nil,
        onOpenUpcoming: (@MainActor () -> Void)? = nil,
        onShowMiniCalendar: (@MainActor () -> Void)? = nil,
        onOpenTray: (@MainActor (UUIDv7) -> Void)? = nil,
        windowActions: WindowMenuActions? = nil
    ) {
        self.model = model
        #if canImport(AppKit)
        self.onDrop = onDrop
        #endif
        self.onOpenUpcoming = onOpenUpcoming
        self.onShowMiniCalendar = onShowMiniCalendar
        self.onOpenTray = onOpenTray
        self.windowActions = windowActions
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
        onFocusTask: (@MainActor (UUIDv7) -> Void)? = nil,
        onDrop: (@MainActor ([NSItemProvider], UUIDv7?) -> Bool)? = nil,
        onOpenUpcoming: (@MainActor () -> Void)? = nil,
        onShowMiniCalendar: (@MainActor () -> Void)? = nil,
        onOpenTray: (@MainActor (UUIDv7) -> Void)? = nil,
        windowActions: WindowMenuActions? = nil
    ) {
        self.model = TodayViewModel(
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            settingRepository: settingRepository,
            calendar: calendar,
            deviceId: deviceId,
            onOpenTask: onOpenTask,
            onFocusTask: onFocusTask
        )
        #if canImport(AppKit)
        self.onDrop = onDrop
        #endif
        self.onOpenUpcoming = onOpenUpcoming
        self.onShowMiniCalendar = onShowMiniCalendar
        self.onOpenTray = onOpenTray
        self.windowActions = windowActions
    }

    private var motion: Motion {
        Motion(preference: reduceMotion ? .reduced : .full)
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                dateHeader
                weekStrip
                if model.isViewingToday {
                    ProgressHeaderView(progress: model.progress, motion: motion)
                    if model.plannedMinutes > 0 {
                        loadMeter
                    }
                } else {
                    futureDaySummary
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

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

            TrayStripView(model: model, onOpenTray: onOpenTray)
                .padding(.top, 2)

            if isSearching {
                searchField
            }

            if let lastError = model.lastError {
                errorBanner(lastError)
            }

            if model.isViewingToday,
               let dueSoon = model.visibleRows.first(where: \.isDueSoon)
            {
                dueSoonBanner(dueSoon)
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
        .background(DesignTokens.Palette.background)
        .overlay(alignment: .top) {
            DesignTokens.Palette.aurora
                .frame(height: 240)
                .allowsHitTesting(false)
        }
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
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            Task { @MainActor in
                await model.load()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.captureSaved)) { note in
            guard let message = note.userInfo?["message"] as? String else { return }
            showCaptureConfirmation(message)
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
        .overlay(alignment: .top) { captureToast }
        .tint(DesignTokens.Palette.accent)
        .task { await model.observe() }
    }

    @MainActor
    private func showCaptureConfirmation(_ message: String) {
        captureConfirmation = message
        captureToastTask?.cancel()
        captureToastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            captureConfirmation = nil
        }
    }

    /// A visible confirmation after capture, especially when the task was
    /// scheduled for tomorrow/Upcoming rather than today.
    @MainActor
    @ViewBuilder
    private var captureToast: some View {
        if let captureConfirmation {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "#0ca30c"))

                Text(captureConfirmation)
                    .font(.caption)
                    .lineLimit(3)

                Spacer(minLength: 0)

                Button {
                    self.captureConfirmation = nil
                    captureToastTask?.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
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
                .stroke(DesignTokens.Palette.accent, lineWidth: 2)
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

                if model.isViewingToday, !model.upcomingRows.isEmpty {
                    upcomingSection
                }

                if model.visibleRows.isEmpty && model.visibleDoneRows.isEmpty
                    && model.upcomingRows.isEmpty
                {
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
            },
            allTrays: model.trays,
            onAddToTray: { itemId, trayId in
                Task { @MainActor in
                    await model.addToTray(itemId, trayId: trayId)
                }
            }
        )

        #if canImport(AppKit)
        return content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(dropTargetId == row.id ? DesignTokens.Palette.accent.opacity(0.12) : Color.clear)
            }
            .onDrop(
                of: CaptureDropTypes.supported,
                isTargeted: dropBinding(for: row.id)
            ) { providers in
                // FR-04: a drop on a row adds attachments to that task.
                onDrop?(providers, row.id) ?? false
            }
            .overlay(alignment: .trailing) {
                if dropTargetId == row.id {
                    Text("Attach")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(DesignTokens.Palette.accent))
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        #else
        return content
        #endif
    }

    // MARK: - Day header / week strip

    @MainActor
    private var dateHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.isViewingToday
                ? "Today"
                : model.activeDay.formatted(.dateTime.weekday(.wide))
            )
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(DesignTokens.Palette.textPrimary)

            Text(model.activeDay.formatted(.dateTime.month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(DesignTokens.Palette.textSecondary)

            Spacer()

            if !model.isViewingToday {
                Button("Back to today") {
                    Task { @MainActor in await model.goToToday() }
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Palette.accent)
                .help("Return to today")
            }

            if let onShowMiniCalendar {
                Button {
                    onShowMiniCalendar()
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Minimize to the mini day/week calendar")
                .accessibilityLabel("Minimize to mini calendar")
            }

            if let windowActions {
                Menu {
                    Button("Dock windows to edges") {
                        windowActions.toggleDocking()
                    }
                    Button("Show windows on all desktops") {
                        windowActions.toggleAllDesktops()
                    }
                    Divider()
                    Button("Show / hide mini calendar") {
                        windowActions.toggleMiniCalendar()
                    }
                    Button("Mini calendar: Day") {
                        windowActions.showMiniDay()
                    }
                    Button("Mini calendar: Week") {
                        windowActions.showMiniWeek()
                    }
                    Menu("Pin mini calendar") {
                        ForEach(ScreenCorner.allCases) { corner in
                            Button(corner.label) {
                                windowActions.pinMiniCalendar(corner)
                            }
                        }
                        Divider()
                        Button("Unpin") {
                            windowActions.pinMiniCalendar(nil)
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Window docking, desktops, and mini-calendar corners")
                .accessibilityLabel("Window options")
            }
        }
        .padding(.horizontal, 4)
    }

    @MainActor
    private var weekStrip: some View {
        HStack(spacing: 3) {
            ForEach(model.weekDays) { day in
                Button {
                    Task { @MainActor in await model.selectDay(day.date) }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(day.isSelected ? Color.white.opacity(0.8) : .secondary)

                        Text(day.date.formatted(.dateTime.day()))
                            .font(.system(.callout, design: .rounded).weight(.semibold))

                        Circle()
                            .fill(day.isSelected ? Color.white : DesignTokens.Palette.accent)
                            .frame(width: 4, height: 4)
                            .opacity(day.count > 0 ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background {
                        if day.isSelected {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(DesignTokens.Palette.gradient)
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(DesignTokens.Palette.surface)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                day.isToday && !day.isSelected
                                    ? DesignTokens.Palette.accent.opacity(0.65)
                                    : DesignTokens.Palette.hairline,
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(
                        day.isSelected
                            ? Color.white
                            : (day.isToday
                                ? DesignTokens.Palette.accent
                                : DesignTokens.Palette.textPrimary)
                    )
                    .shadow(
                        color: day.isSelected ? DesignTokens.Palette.accent.opacity(0.35) : .clear,
                        radius: 6,
                        y: 2
                    )
                }
                .buttonStyle(.plain)
                .help("\(day.count) task\(day.count == 1 ? "" : "s") due")
                .accessibilityLabel(
                    "\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) tasks"
                )
            }
        }
    }

    @MainActor
    private var loadMeter: some View {
        let planned = model.plannedMinutes
        let capacity = max(1, model.capacityMinutes)
        let fraction = min(1, Double(planned) / Double(capacity))
        let over = planned > capacity

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label("\(minutesLabel(planned)) planned", systemImage: "gauge.with.dots.needle.33percent")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        over ? DesignTokens.Palette.warning : DesignTokens.Palette.textSecondary
                    )
                Spacer()
                Text("of \(minutesLabel(capacity))")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(over ? DesignTokens.Palette.warning : DesignTokens.Palette.accent)
                .scaleEffect(x: 1, y: 0.65, anchor: .center)

            if over {
                Text("Overbooked by \(minutesLabel(planned - capacity)) — move something.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.warning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Palette.surface.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
        .help("Estimated effort across today's open tasks")
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    @MainActor
    private var futureDaySummary: some View {
        let ring = ProgressRingModel(done: model.progress.done, total: model.progress.total)
        return HStack(spacing: 12) {
            ProgressRingView(model: ring, tint: DesignTokens.Palette.accent, motion: motion)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.progress.remaining) planned")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(ring.doneLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Pick a task to work ahead")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
        .shadow(color: DesignTokens.Palette.shadow, radius: 10, y: 4)
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
        .padding(.top, 10)
        .padding(.bottom, 3)
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Tomorrow & upcoming")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(model.upcomingRows.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if let onOpenUpcoming {
                    Button("See all") {
                        onOpenUpcoming()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 3)

            ForEach(model.upcomingRows) { row in
                upcomingRow(row)
            }
        }
    }

    @MainActor
    private func upcomingRow(_ row: TodayViewModel.UpcomingRow) -> some View {
        HStack(spacing: 4) {
            Button {
                model.onOpenTask?(row.id)
            } label: {
                HStack(spacing: 8) {
                    if let color = row.parentColorHex {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: color))
                            .frame(width: 3, height: 16)
                    }

                    Circle()
                        .fill(PriorityColor.color(for: row.priority, in: colorScheme))
                        .frame(width: 7, height: 7)

                    Text(row.title)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(upcomingLabel(row.dueAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrag {
                WorkItemDragPayload.itemProvider(for: row.id)
            }

            Menu {
                if !model.trays.isEmpty {
                    Menu("Add to tray") {
                        ForEach(model.trays) { tray in
                            Button(tray.name) {
                                Task { await model.addToTray(row.id, trayId: tray.id) }
                            }
                        }
                    }
                }

                Menu("Priority") {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button {
                            Task { await model.setUpcomingPriority(row.id, priority) }
                        } label: {
                            HStack {
                                Text(priority.label)
                                if priority == row.priority {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Menu("Start time") {
                    Button("Now") {
                        Task { await model.setUpcomingStart(row.id, to: .now) }
                    }
                    Button("Tomorrow at 9:00") {
                        Task { await model.setUpcomingStart(row.id, to: startTime(daysAhead: 1)) }
                    }
                    Button("Next Monday at 9:00") {
                        Task { await model.setUpcomingStart(row.id, to: nextMonday()) }
                    }
                    Button("Tomorrow at end of day") {
                        Task { await model.setUpcomingStart(row.id, to: tomorrowEndOfDay()) }
                    }
                }

                Divider()

                Button("Move up") {
                    Task { await model.moveUpcomingUp(row.id) }
                }
                Button("Move down") {
                    Task { await model.moveUpcomingDown(row.id) }
                }

                Divider()

                Button("Open") {
                    model.onOpenTask?(row.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.trailing, 8)
            .accessibilityLabel("Plan \(row.title)")
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.028))
        )
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private func startTime(daysAhead: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(
            byAdding: .day,
            value: daysAhead,
            to: calendar.startOfDay(for: .now)
        ) ?? .now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base
    }

    private func tomorrowEndOfDay() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: .now)
        ) ?? .now
        return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func nextMonday() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = calendar.component(.weekday, from: today)
        var days = (2 - weekday + 7) % 7
        if days == 0 { days = 7 }
        let monday = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
    }

    private func upcomingLabel(_ date: Date) -> String {
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    // MARK: - Due soon

    @MainActor
    private func dueSoonBanner(_ row: TaskRowModel) -> some View {
        let minutes = max(1, Int(row.dueAt.timeIntervalSinceNow / 60))
        return HStack(spacing: 9) {
            Image(systemName: "clock.fill")
                .foregroundStyle(DesignTokens.Palette.warning)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

            VStack(alignment: .leading, spacing: 1) {
                Text("Due soon · \(minutes) min")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.warning)

                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    DesignTokens.Palette.warning.opacity(0.16),
                    DesignTokens.Palette.warning.opacity(0.05),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.Palette.warning)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Due soon, \(row.title), \(minutes) minutes")
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
        if !model.isViewingToday, model.progress.total == 0 {
            return "Nothing planned"
        } else if model.progress.total == 0 {
            return "Nothing scheduled"
        } else if model.progress.isCleared {
            return "Day cleared"
        } else {
            return "No matching tasks"
        }
    }

    @MainActor
    private var emptySubtitle: String {
        if !model.isViewingToday, model.progress.total == 0 {
            return "Pick another day in the week strip, or add a task from Today."
        } else if model.progress.total == 0 {
            return "Drop something anywhere, or press ⌃⌥Space to add a task."
        } else if model.progress.isCleared {
            return "Everything on this day is done."
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
