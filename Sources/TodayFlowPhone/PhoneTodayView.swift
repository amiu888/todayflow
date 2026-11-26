#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// The Today tab (docs/ios/DESIGN.md §3.1): progress, week strip, filter
/// chips, and the Overdue / Today / Upcoming / Done sections. All state and
/// rules come from the Mac's `TodayViewModel`.
struct PhoneTodayView: View {
    @Bindable var model: TodayViewModel
    let environment: PhoneEnvironment
    var onAdd: () -> Void
    var onSettings: () -> Void

    @State private var showUpcoming = false
    @State private var showDone = false
    @State private var priorityTarget: UUIDv7?
    @State private var deleteTarget: UUIDv7?
    @State private var showsUndoBar = false
    @State private var openTray: PhoneTrayRoute?

    var body: some View {
        List {
            Section {
                PhoneTodayHeader(model: model)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if model.isViewingToday {
                Section {
                    PhoneTrayStrip(model: model) { openTray = PhoneTrayRoute(id: $0) }
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Trays")
                }
            }

            rowSection("Overdue", rows: model.visibleOverdueRows, tint: .red)
            rowSection(model.isViewingToday ? "Today" : dayTitle, rows: model.visibleOpenRows, tint: nil)

            if model.isViewingToday, !model.upcomingRows.isEmpty {
                Section(isExpanded: $showUpcoming) {
                    ForEach(model.upcomingRows) { row in
                        NavigationLink(value: row.id) { PhoneUpcomingRow(row: row) }
                            .contextMenu { menu(for: row.id) }
                    }
                } header: {
                    Text("Upcoming · \(model.upcomingRows.count)")
                }
            }

            if !model.visibleDoneRows.isEmpty {
                Section(isExpanded: $showDone) {
                    ForEach(model.visibleDoneRows) { row in
                        NavigationLink(value: row.id) {
                            PhoneTaskRow(row: row, project: model.project(of: row.id)?.title) {
                                Task { await model.toggle(row.id) }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button("Reopen", systemImage: "arrow.uturn.backward") {
                                Task { await model.toggle(row.id) }
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    Text("Done · \(model.visibleDoneRows.count)")
                }
            }

            if isEmpty {
                ContentUnavailableView(
                    "Nothing planned",
                    systemImage: "sun.max",
                    description: Text("Tap ＋ to add a task.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(model.isViewingToday ? "Today" : dayTitle)
        .navigationDestination(item: $openTray) { route in
            PhoneTrayDetailView(model: model, trayId: route.id, environment: environment)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Picker("Sort", selection: Binding(
                        get: { model.sort },
                        set: { new in Task { await model.setSort(new) } }
                    )) {
                        ForEach(TodaySort.allCases) { Text($0.label).tag($0) }
                    }
                    if !model.isViewingToday {
                        Button("Back to Today", systemImage: "arrow.uturn.backward") {
                            Task { await model.goToToday() }
                        }
                    }
                    Divider()
                    Button("Settings", systemImage: "gear", action: onSettings)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Task", systemImage: "plus", action: onAdd)
            }
        }
        .refreshable {
            await model.reloadTrays()
            await model.load()
        }
        .overlay(alignment: .bottom) { undoBar }
        .animation(.snappy, value: showsUndoBar)
        .task(id: model.completionUndo) {
            showsUndoBar = model.completionUndo != nil
            guard showsUndoBar else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { showsUndoBar = false }
        }
        .confirmationDialog("Priority", isPresented: isPresented($priorityTarget), titleVisibility: .visible) {
            if let id = priorityTarget {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button(priority.label) {
                        Task { await model.quickAction(id, .setPriority(priority)) }
                    }
                }
            }
        }
        .confirmationDialog("Delete this task?", isPresented: isPresented($deleteTarget), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = deleteTarget { Task { await delete(id) } }
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func rowSection(_ title: String, rows: [TaskRowModel], tint: Color?) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    NavigationLink(value: row.id) {
                        PhoneTaskRow(row: row, project: model.project(of: row.id)?.title) {
                            Task { await model.toggle(row.id) }
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Complete", systemImage: "checkmark") {
                            Task { await model.toggle(row.id) }
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteTarget = row.id
                        }
                        Button("Priority", systemImage: "flag") { priorityTarget = row.id }
                            .tint(.orange)
                        Button("Tomorrow", systemImage: "arrow.right.circle") {
                            Task { await model.quickAction(row.id, .moveToTomorrow) }
                        }
                        .tint(.blue)
                    }
                    .contextMenu { menu(for: row.id) }
                }
            } header: {
                Text("\(title) · \(rows.count)")
                    .foregroundStyle(tint ?? .secondary)
            }
        }
    }

    /// The long-press menu: the Mac row's right-click actions that fit a phone.
    @ViewBuilder
    private func menu(for id: UUIDv7) -> some View {
        Button("Complete", systemImage: "checkmark.circle") { Task { await model.toggle(id) } }
        Button("Move to Tomorrow", systemImage: "arrow.right.circle") {
            Task { await model.quickAction(id, .moveToTomorrow) }
        }
        Menu("Priority", systemImage: "flag") {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button(priority.label) { Task { await model.quickAction(id, .setPriority(priority)) } }
            }
        }
        if !model.projects.isEmpty {
            Menu("Move to Project", systemImage: "folder") {
                ForEach(model.projects) { project in
                    Button(project.title) { Task { await move(id, to: project.id) } }
                }
            }
        }
        PhoneTrayMenu(model: model, itemId: id)
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = id }
    }

    @ViewBuilder
    private var undoBar: some View {
        if showsUndoBar, model.completionUndo != nil {
            HStack {
                Label("Task completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Undo") { Task { await model.undoComplete() } }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: Helpers

    private var isEmpty: Bool {
        model.visibleOverdueRows.isEmpty && model.visibleOpenRows.isEmpty
            && model.visibleDoneRows.isEmpty && !model.isLoading
    }

    private var dayTitle: String {
        model.activeDay.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func isPresented(_ target: Binding<UUIDv7?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }

    private func delete(_ id: UUIDv7) async {
        _ = try? await DeleteTask(itemRepository: environment.workItems, linkRepository: environment.links)
            .execute(id)
        await model.load()
    }

    private func move(_ id: UUIDv7, to projectId: UUIDv7) async {
        guard var item = await environment.workItems.item(id) else { return }
        item.parentId = projectId
        item.updatedAt = .now
        try? await environment.workItems.save(item)
        await model.load()
    }
}

// MARK: - Header

/// Date, progress and planned load, the week strip, and the filter chips.
struct PhoneTodayHeader: View {
    @Bindable var model: TodayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(model.activeDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                Text("·")
                Text("\(model.progress.done)/\(model.progress.total) done")
                if model.plannedMinutes > 0 {
                    Text("·")
                    Text(Self.duration(model.plannedMinutes))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            ProgressView(value: model.progress.fraction)
                .tint(model.progress.isCleared ? .green : .accentColor)

            PhoneWeekStrip(model: model)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TodayFilter.allCases) { filter in
                        chip(filter.label, selected: model.filter == filter && model.tagFilter == nil) {
                            model.filter = filter
                            model.tagFilter = nil
                        }
                    }
                    if !model.allTags.isEmpty {
                        Menu {
                            Button("Any tag") { model.tagFilter = nil }
                            ForEach(model.allTags, id: \.self) { tag in
                                Button("#\(tag)") { model.tagFilter = tag }
                            }
                        } label: {
                            chipLabel(model.tagFilter.map { "#\($0)" } ?? "#tag ▾", selected: model.tagFilter != nil)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, selected: selected) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: .capsule)
            .foregroundStyle(selected ? Color.accentColor : .primary)
    }

    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)"
    }
}

/// Seven days; a dot marks days with tasks. Swipe or use the arrows to page.
struct PhoneWeekStrip: View {
    @Bindable var model: TodayViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button("Previous week", systemImage: "chevron.left") { model.shiftStrip(by: -1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            ForEach(model.weekDays.prefix(7)) { day in
                Button {
                    Task { await model.selectDay(day.date) }
                } label: {
                    VStack(spacing: 2) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(day.date.formatted(.dateTime.day()))
                            .font(.callout.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday && !day.isSelected ? Color.accentColor : .primary)
                        Circle()
                            .fill(day.count > 0 ? Color.accentColor : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        day.isSelected ? Color.accentColor.opacity(0.18) : .clear,
                        in: .rect(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + ", " + day.tooltip)
            }
            Button("Next week", systemImage: "chevron.right") { model.shiftStrip(by: 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40 { model.shiftStrip(by: 1) }
            if value.translation.width > 40 { model.shiftStrip(by: -1) }
        })
    }
}

// MARK: - Rows

/// One task: check circle, priority pill, title, due time, project and hints.
struct PhoneTaskRow: View {
    let row: TaskRowModel
    let project: String?
    var onToggle: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.isDone ? Color.green : PriorityColor.color(for: row.priority, in: scheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isDone ? "Reopen" : "Complete")

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PriorityPill(priority: row.priority)
                    Text(row.title)
                        .strikethrough(row.isDone)
                        .foregroundStyle(row.isDone ? .secondary : .primary)
                        .lineLimit(2)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(dueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(row.isOverdue ? .red : row.isDueSoon ? .orange : .secondary)
                HStack(spacing: 4) {
                    if row.isBlocked { Image(systemName: "lock.fill") }
                    if row.attachmentCount > 0 { Image(systemName: "paperclip") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        let tags = row.tags.prefix(2).map { "#\($0)" }
        let parts = [project].compactMap { $0 } + tags
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var dueText: String {
        if let done = row.completedAt, row.isDone {
            return done.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInToday(row.dueAt) {
            return row.dueAt.formatted(date: .omitted, time: .shortened)
        }
        return row.dueAt.formatted(.dateTime.weekday(.abbreviated).day())
    }
}

/// A future task in the Upcoming section.
struct PhoneUpcomingRow: View {
    let row: TodayViewModel.UpcomingRow

    var body: some View {
        HStack(spacing: 8) {
            PriorityPill(priority: row.priority)
            Text(row.title).lineLimit(1)
            Spacer()
            Text(row.dueAt.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// "P2" in the priority color.
struct PriorityPill: View {
    let priority: Priority
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = PriorityColor.color(for: priority, in: scheme)
        Text(priority.shortLabel)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.18), in: .capsule)
            .foregroundStyle(color)
            .accessibilityLabel(priority.label)
    }
}
/// Opens a tray from the strip (tray ids are UUIDs like task ids, so they
/// get their own type for navigation).
struct PhoneTrayRoute: Hashable, Identifiable {
    let id: UUIDv7
}
#endif
