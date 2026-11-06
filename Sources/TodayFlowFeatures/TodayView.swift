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
    private let onOpenContacts: (@MainActor () -> Void)?
    private let dockedApp: AppDockState?
    private let onDockToApp: (@MainActor (String, String) -> Void)?
    private let onUndockApp: (@MainActor () -> Void)?
    private let dockedAppProvider: (@MainActor () -> AppDockState?)?
    private let windowActions: WindowMenuActions?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("todayflow.allDesktops") private var showOnAllDesktops = false
    @State private var isSearching: Bool = false
    @State private var searchText: String = ""
    @State private var isPanelDropTargeted: Bool = false
    @State private var dropTargetId: UUIDv7?
    @State private var showsUndoBar = false
    @State private var undoBarTask: Task<Void, Never>?
    @State private var captureConfirmation: String?
    @State private var captureToastTask: Task<Void, Never>?
    @State private var showingDockPopover = false
    @State private var dockAppBundle = ""
    @State private var dockEdge = "left"
    @State private var localDockedName: String?
    @State private var isCompact = false
    @State private var showingNewProject = false
    @State private var newProjectName = ""

    public init(model: TodayViewModel) {
        self.model = model
        #if canImport(AppKit)
        self.onDrop = nil
        #endif
        self.onOpenUpcoming = nil
        self.onShowMiniCalendar = nil
        self.onOpenTray = nil
        self.onOpenContacts = nil
        self.dockedApp = nil
        self.onDockToApp = nil
        self.onUndockApp = nil
        self.dockedAppProvider = nil
        self.windowActions = nil
        _localDockedName = State(initialValue: nil)
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
        onOpenContacts: (@MainActor () -> Void)? = nil,
        dockedApp: AppDockState? = nil,
        onDockToApp: (@MainActor (String, String) -> Void)? = nil,
        onUndockApp: (@MainActor () -> Void)? = nil,
        dockedAppProvider: (@MainActor () -> AppDockState?)? = nil,
        windowActions: WindowMenuActions? = nil
    ) {
        self.model = model
        #if canImport(AppKit)
        self.onDrop = onDrop
        #endif
        self.onOpenUpcoming = onOpenUpcoming
        self.onShowMiniCalendar = onShowMiniCalendar
        self.onOpenTray = onOpenTray
        self.onOpenContacts = onOpenContacts
        self.dockedApp = dockedApp
        self.onDockToApp = onDockToApp
        self.onUndockApp = onUndockApp
        self.dockedAppProvider = dockedAppProvider
        self.windowActions = windowActions
        _localDockedName = State(
            initialValue: dockedApp?.isDocked == true ? dockedApp?.appName : nil
        )
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
        onOpenContacts: (@MainActor () -> Void)? = nil,
        dockedApp: AppDockState? = nil,
        onDockToApp: (@MainActor (String, String) -> Void)? = nil,
        onUndockApp: (@MainActor () -> Void)? = nil,
        dockedAppProvider: (@MainActor () -> AppDockState?)? = nil,
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
        self.onOpenContacts = onOpenContacts
        self.dockedApp = dockedApp
        self.onDockToApp = onDockToApp
        self.onUndockApp = onUndockApp
        self.dockedAppProvider = dockedAppProvider
        self.windowActions = windowActions
        _localDockedName = State(
            initialValue: dockedApp?.isDocked == true ? dockedApp?.appName : nil
        )
    }

    private var motion: Motion {
        Motion(preference: reduceMotion ? .reduced : .full)
    }

    @MainActor
    public var body: some View {
        GeometryReader { proxy in
            // Below 320 points, lay the single-column UI out at 320 and
            // scale it into the available width. This keeps every control
            // visible instead of clipping the left/right edge when the
            // window is squeezed.
            let baseWidth: CGFloat = 320
            let scale = min(1, proxy.size.width / baseWidth)
            let contentWidth = max(proxy.size.width, baseWidth)
            let contentHeight = proxy.size.height / max(scale, 0.01)

            panelBody
                .frame(
                    width: contentWidth,
                    height: contentHeight,
                    alignment: .topLeading
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .topLeading
                )
                .onAppear {
                    isCompact = proxy.size.width < 340
                }
                .onChange(of: proxy.size.width) { _, width in
                    isCompact = width < 340
                }
        }
    }

    @MainActor
    private var panelBody: some View {
        VStack(spacing: 0) {
            panelHeader

            filterBar

            if !isCompact {
                trayStrip
            }

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
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.itemsChanged)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.captureSaved)) { note in
            handleCaptureSaved(note)
        }
        .onChange(of: model.completionUndo) { _, undo in
            updateUndoBar(for: undo)
        }
        .overlay(alignment: .bottom) { undoBar }
        .overlay(alignment: .top) { captureToast }
        .alert("New project", isPresented: $showingNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { newProjectName = "" }
            Button("Create") {
                let name = newProjectName
                newProjectName = ""
                Task { @MainActor in
                    if let project = await model.createProject(named: name) {
                        showCaptureConfirmation("Created project “\(project.title)”")
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            Text("Projects group related tasks and appear in the project filter and Hierarchy.")
        }
        .tint(DesignTokens.Palette.accent)
        .task { await model.observe() }
    }

    @MainActor
    private var trayStrip: some View {
        TrayStripView(
            model: model,
            onOpenTray: onOpenTray,
            isCompact: isCompact
        )
        .padding(.top, 2)
    }

    @MainActor
    private var filterBar: some View {
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
    }

    @MainActor
    private var panelHeader: some View {
        VStack(spacing: 6) {
            dateHeader

            // One compact surface holds the week strip and the day's status
            // row; the old design used three separate cards.
            dayStatusCard

            if model.isViewingToday, model.plannedMinutes > 0 {
                loadMeter
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    @MainActor
    private var dayStatusCard: some View {
        VStack(spacing: 0) {
            if isCompact {
                verticalWeekStrip
            } else {
                weekStrip
                    .padding(.horizontal, 3)
                    .padding(.vertical, 3)
            }

            Divider()
                .overlay(DesignTokens.Palette.hairline.opacity(0.7))

            if model.isViewingToday {
                ProgressHeaderView(progress: model.progress, motion: motion)
            } else {
                futureDaySummary
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
    }

    private func reload() {
        Task { @MainActor in
            await model.load()
        }
    }

    @MainActor
    private func handleCaptureSaved(_ note: Notification) {
        guard let message = note.userInfo?["message"] as? String else { return }
        showCaptureConfirmation(message)
    }

    @MainActor
    private func updateUndoBar(for undo: TodayViewModel.CompletionUndo?) {
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
            VStack(spacing: 0) {
                if isCompact {
                    trayStrip
                        .padding(.bottom, 2)
                    Divider()
                        .padding(.horizontal, 12)
                }

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
            },
            isCompact: isCompact
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
        Group {
            if isCompact {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    titleAndDate
                    Spacer(minLength: 4)
                    if !model.isViewingToday {
                        backToTodayButton
                    }
                }
                    HStack(spacing: 9) {
                        Spacer(minLength: 0)
                        headerActionIcons
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    titleAndDate
                    Spacer(minLength: 6)
                    if !model.isViewingToday {
                        backToTodayButton
                    }
                    headerActionIcons
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @MainActor
    private var titleAndDate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(model.isViewingToday
                ? "Today"
                : model.activeDay.formatted(.dateTime.weekday(.wide))
            )
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(DesignTokens.Palette.textPrimary)

            Text(model.activeDay.formatted(.dateTime.month(.wide).day()))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
    }

    @MainActor
    private var backToTodayButton: some View {
        Button("Back to today") {
            Task { @MainActor in await model.goToToday() }
        }
        .buttonStyle(.borderless)
        .font(.caption.weight(.semibold))
        .foregroundStyle(DesignTokens.Palette.accent)
        .help("Return to today")
    }

    @MainActor
    @ViewBuilder
    private var headerActionIcons: some View {
        HStack(spacing: 9) {
            if let windowActions {
                Button {
                    windowActions.toggleAllDesktops()
                } label: {
                    Image(systemName: "anchor")
                        .font(.caption)
                        .foregroundStyle(
                            showOnAllDesktops
                                ? DesignTokens.Palette.textSecondary
                                : DesignTokens.Palette.accent
                        )
                }
                .buttonStyle(.plain)
                .help(showOnAllDesktops
                    ? "Shown on all desktops — click to anchor to this one"
                    : "Anchored to this desktop — click to show on all desktops")
                .accessibilityLabel(showOnAllDesktops
                    ? "Anchor Today to this desktop"
                    : "Show Today on all desktops")
                .accessibilityIdentifier("anchor-to-desktop")
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

            Button {
                newProjectName = ""
                showingNewProject = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Create a project")
            .accessibilityLabel("New project")
            .accessibilityIdentifier("new-project")

            if let onOpenContacts {
                Button {
                    onOpenContacts()
                } label: {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Open contacts")
                .accessibilityLabel("Open contacts")
            }

            if onDockToApp != nil {
                Button {
                    refreshDockState()
                    prepareDockPopover()
                    showingDockPopover = true
                } label: {
                    Image(systemName: localDockedName == nil ? "pin" : "pin.fill")
                        .font(.caption)
                        .foregroundStyle(
                            localDockedName == nil
                                ? DesignTokens.Palette.textSecondary
                                : DesignTokens.Palette.accent
                        )
                }
                .buttonStyle(.plain)
                .help(dockHelp)
                .accessibilityLabel("Dock to application")
                .popover(isPresented: $showingDockPopover, arrowEdge: .bottom) {
                    dockPopover
                }
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
    }

    private var dockHelp: String {
        if let name = localDockedName {
            return "Docked to \(name) — click to change"
        }
        return "Dock to another application"
    }

    @MainActor
    private func refreshDockState() {
        guard let state = dockedAppProvider?() else { return }
        localDockedName = state.isDocked ? state.appName : nil
        dockEdge = state.edge
    }

    @MainActor
    private func prepareDockPopover() {
        dockEdge = dockedApp?.edge ?? "left"
        if let current = localDockedName,
           let match = runningApps.first(where: { $0.name == current })
        {
            dockAppBundle = match.bundleId
        } else if dockAppBundle.isEmpty {
            dockAppBundle = runningApps.first?.bundleId ?? ""
        }
    }

    #if canImport(AppKit)
    private var runningApps: [(bundleId: String, name: String)] {
        let visiblePIDs = Set(
            (CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] ?? [])
            .compactMap { info -> pid_t? in
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0
                else { return nil }
                return info[kCGWindowOwnerPID as String] as? pid_t
            }
        )
        return NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    && visiblePIDs.contains($0.processIdentifier)
            }
            .compactMap { app in
                guard let id = app.bundleIdentifier,
                      let name = app.localizedName,
                      !name.isEmpty
                else { return nil }
                return (id, name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var dockPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dock TodayFlow")
                .font(.headline)

            Picker("Application", selection: $dockAppBundle) {
                ForEach(runningApps, id: \.bundleId) { app in
                    Text(app.name).tag(app.bundleId)
                }
            }
            .disabled(runningApps.isEmpty)

            Picker("Attach to", selection: $dockEdge) {
                Text("Left").tag("left")
                Text("Right").tag("right")
                Text("Top").tag("top")
                Text("Bottom").tag("bottom")
            }
            .pickerStyle(.segmented)

            if runningApps.isEmpty {
                Text("Open another app first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Dock") {
                    guard !dockAppBundle.isEmpty else { return }
                    let name = runningApps.first { $0.bundleId == dockAppBundle }?.name
                    onDockToApp?(dockAppBundle, dockEdge)
                    localDockedName = name ?? dockAppBundle
                    showingDockPopover = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(dockAppBundle.isEmpty)

                if localDockedName != nil {
                    Button("Undock") {
                        onUndockApp?()
                        localDockedName = nil
                        showingDockPopover = false
                    }
                }

                Spacer()

                Button("Cancel") {
                    showingDockPopover = false
                }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
    #else
    private var runningApps: [(bundleId: String, name: String)] { [] }
    private var dockPopover: some View { EmptyView() }
    #endif

    @MainActor
    private var weekStrip: some View {
        HStack(spacing: 2) {
            ForEach(model.weekDays) { day in
                Button {
                    Task { @MainActor in await model.selectDay(day.date) }
                } label: {
                    VStack(spacing: 1) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                day.isSelected ? Color.white.opacity(0.78) : .secondary
                            )

                        Text(day.date.formatted(.dateTime.day()))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()

                        Circle()
                            .fill(day.isSelected ? Color.white : DesignTokens.Palette.accent)
                            .frame(width: 3, height: 3)
                            .opacity(day.count > 0 ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background {
                        if day.isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DesignTokens.Palette.gradient)
                        } else if day.isToday {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DesignTokens.Palette.accent.opacity(0.10))
                        }
                    }
                    .foregroundStyle(
                        day.isSelected
                            ? Color.white
                            : (day.isToday
                                ? DesignTokens.Palette.accent
                                : DesignTokens.Palette.textPrimary)
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
    private var verticalWeekStrip: some View {
        VStack(spacing: 0) {
            ForEach(model.weekDays) { day in
                Button {
                    Task { @MainActor in await model.selectDay(day.date) }
                } label: {
                    HStack(spacing: 8) {
                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                day.isSelected
                                    ? DesignTokens.Palette.accent
                                    : DesignTokens.Palette.textSecondary
                            )
                            .frame(width: 34, alignment: .leading)

                        Text(day.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                day.isSelected
                                    ? DesignTokens.Palette.textPrimary
                                    : DesignTokens.Palette.textPrimary
                            )

                        Spacer(minLength: 0)

                        if day.count > 0 {
                            Text("\(day.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                        }

                        if day.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.Palette.accent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        if day.isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DesignTokens.Palette.accent.opacity(0.13))
                        } else if day.isToday {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DesignTokens.Palette.accent.opacity(0.06))
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("\(day.count) task\(day.count == 1 ? "" : "s") due")
                .accessibilityLabel(
                    "\(day.date.formatted(date: .complete, time: .omitted)), \(day.count) tasks"
                )
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
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
        return HStack(spacing: 7) {
            ProgressRingView(
                model: ring,
                size: 20,
                tint: DesignTokens.Palette.accent,
                motion: motion
            )

            Text("\(model.progress.remaining) planned")
                .font(.caption.weight(.semibold))
                .monospacedDigit()

            Text(ring.doneLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("Work ahead")
                .font(.caption2.weight(.medium))
                .foregroundStyle(DesignTokens.Palette.accent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
