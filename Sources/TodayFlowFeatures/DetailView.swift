import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign
#if canImport(AppKit)
import AppKit
#endif

/// The Jira-style task detail window (driver.md FR-20, FR-21, FR-22):
/// breadcrumb, editable title, status / priority pills, dates with shortcuts,
/// markdown description, subtasks, attachments, links, and the action row.
///
/// Pure presentation — all logic lives in `DetailViewModel`. FR-23's
/// AppKit-heavy parts (Quick Look, Reveal in Finder, live markdown rendering)
/// belong to the 6 Mac app layer, which swaps them in around this view.
public struct DetailView: View {
    public let model: DetailViewModel
    private let onOpenAttachment: (@MainActor (Attachment) -> Void)?
    private let onOpenAttachmentWith: (@MainActor (Attachment) -> Void)?
    private let defaultApplicationName: (@MainActor (Attachment) -> String?)?
    private let onQuickLookAttachment: (@MainActor (Attachment) -> Void)?
    private let onRevealAttachment: (@MainActor (Attachment) -> Void)?
    #if canImport(AppKit)
    private let onDropAttachment: (@MainActor ([NSItemProvider]) -> Bool)?
    #endif

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var selectedSuggestions: Set<String> = []
    @State private var isAttachmentDropTargeted = false
    @State private var showSaved = false
    @State private var savedFeedbackTask: Task<Void, Never>?
    @State private var newTag = ""

    /// The two focusable text fields.
    private enum Field: Hashable {
        case title
        case description
    }

    private var motion: Motion {
        Motion(preference: reduceMotion ? .reduced : .full)
    }

    public init(
        model: DetailViewModel,
        onOpenAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onOpenAttachmentWith: (@MainActor (Attachment) -> Void)? = nil,
        defaultApplicationName: (@MainActor (Attachment) -> String?)? = nil,
        onQuickLookAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onRevealAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onDropAttachment: (@MainActor ([NSItemProvider]) -> Bool)? = nil
    ) {
        self.model = model
        self.onOpenAttachment = onOpenAttachment
        self.onOpenAttachmentWith = onOpenAttachmentWith
        self.defaultApplicationName = defaultApplicationName
        self.onQuickLookAttachment = onQuickLookAttachment
        self.onRevealAttachment = onRevealAttachment
        #if canImport(AppKit)
        self.onDropAttachment = onDropAttachment
        #endif
    }

    /// Convenience for hosts that only know the item id and their
    /// repositories (the 6 Mac app layer uses this).
    @MainActor
    public init(
        itemId: UUIDv7,
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        attachmentRepository: any AttachmentRepository,
        onClosed: (@MainActor () -> Void)? = nil,
        onOpenAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onOpenAttachmentWith: (@MainActor (Attachment) -> Void)? = nil,
        defaultApplicationName: (@MainActor (Attachment) -> String?)? = nil,
        onQuickLookAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onRevealAttachment: (@MainActor (Attachment) -> Void)? = nil,
        onDropAttachment: (@MainActor ([NSItemProvider]) -> Bool)? = nil
    ) {
        self.model = DetailViewModel(
            itemId: itemId,
            repository: repository,
            linkRepository: linkRepository,
            attachmentRepository: attachmentRepository,
            onClosed: onClosed
        )
        self.onOpenAttachment = onOpenAttachment
        self.onOpenAttachmentWith = onOpenAttachmentWith
        self.defaultApplicationName = defaultApplicationName
        self.onQuickLookAttachment = onQuickLookAttachment
        self.onRevealAttachment = onRevealAttachment
        #if canImport(AppKit)
        self.onDropAttachment = onDropAttachment
        #endif
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
        #if canImport(AppKit)
        // Dropping a file anywhere on the detail window attaches it to this
        // task (FR-04). This is the natural place to add a screenshot/PDF
        // after the task exists.
        .onDrop(
            of: CaptureDropTypes.supported,
            isTargeted: $isAttachmentDropTargeted
        ) { providers in
            onDropAttachment?(providers) ?? false
        }
        #endif
        .tint(DesignTokens.Palette.accent)
        .task { await model.load() }
        .onReceive(NotificationCenter.default.publisher(for: TodayFlowEvents.attachmentsChanged)) { _ in
            Task { @MainActor in await model.load() }
        }
        .onChange(of: model.subtaskSuggestions) { _, new in
            selectedSuggestions = Set(new.map(\.title))
        }
        .onChange(of: model.lastSavedAt) { _, saved in
            guard saved != nil else { return }
            savedFeedbackTask?.cancel()
            withAnimation(.easeOut(duration: 0.18)) { showSaved = true }
            savedFeedbackTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.25)) { showSaved = false }
            }
        }
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
                    tagsRow(item)
                    datesRow
                    HStack(spacing: 10) {
                        if model.remindersAvailable {
                            reminderSection
                        }
                        estimateMenu
                    }
                    descriptionSection

                    if model.assistant != nil {
                        aiBreakdownSection
                    }

                    if !model.children.isEmpty {
                        childrenSection
                    }
                    if !model.attachments.isEmpty {
                        attachmentsSection
                    }

                    linksSection

                    if !model.activity.isEmpty {
                        activitySection
                    }

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

            if model.isSaving {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Saving…")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if showSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.success)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityLabel("Changes saved")
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
        .help("Change status")
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
        .help("Change priority")
    }

    @MainActor
    private func tagsRow(_ item: WorkItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)

            ForEach(item.tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text(tag)
                        .font(.caption2.weight(.medium))
                    Button {
                        Task { await model.removeTag(tag) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove tag")
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(DesignTokens.Palette.accent.opacity(0.16)))
                .foregroundStyle(DesignTokens.Palette.accent)
            }

            TextField("Add tag", text: $newTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 78)
                .onSubmit {
                    let value = newTag
                    newTag = ""
                    Task { await model.addTag(value) }
                }
                .help("Type a tag and press Return")

            Spacer()
        }
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
    private var estimateMenu: some View {
        let current = model.edit.estimatedMinutes

        return Menu {
            Button("No estimate") {
                model.edit.estimatedMinutes = nil
                Task { await model.commit() }
            }
            Divider()
            ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                Button(minutesLabel(minutes)) {
                    model.edit.estimatedMinutes = minutes
                    Task { await model.commit() }
                }
            }
        } label: {
            Label(
                current.map(minutesLabel) ?? "Estimate",
                systemImage: "timer"
            )
            .font(.caption)
            .foregroundStyle(
                current == nil
                    ? DesignTokens.Palette.textSecondary
                    : DesignTokens.Palette.accent
            )
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Effort estimate, used by the daily load meter")
    }

    private func minutesLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest)m" }
        if rest == 0 { return "\(hours)h" }
        return "\(hours)h \(rest)m"
    }

    /// Per-task custom reminder (FR-42). Distinct from the automatic
    /// end-of-day nudges; setting one suppresses the automatic task nudge.
    @MainActor
    private var reminderSection: some View {
        @Bindable var model = model

        return HStack(spacing: 8) {
            Label("Reminder", systemImage: "bell")
                .font(.callout)
                .foregroundStyle(DesignTokens.Palette.textSecondary)

            DatePicker(
                "",
                selection: $model.reminderDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .accessibilityLabel("Reminder time")

            Button(model.reminder == nil ? "Set" : "Update") {
                Task { await model.setReminder(at: model.reminderDate) }
            }
            .disabled(model.isSaving)

            if model.reminder != nil {
                Button("Remove") {
                    Task { await model.clearReminder() }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(model.isSaving)
            }

            Spacer()
        }
        .font(.callout)
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

    /// "Break down" (driver.md §8): AI suggestions checked by default, then
    /// added only when the user explicitly chooses "Add selected".
    @MainActor
    private var aiBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Break down with AI", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Button(model.subtaskSuggestions.isEmpty ? "Suggest subtasks" : "Try again") {
                    Task { await model.requestBreakdown() }
                }
                .disabled(model.isSuggestingSubtasks || model.isSaving)
            }

            if model.isSuggestingSubtasks {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Thinking…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.subtaskSuggestions.isEmpty {
                ForEach(model.subtaskSuggestions) { suggestion in
                    Toggle(isOn: selectionBinding(suggestion.title)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                            if !suggestion.details.isEmpty {
                                Text(suggestion.details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let minutes = suggestion.estimatedMinutes {
                                Text("\(minutes) min")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                HStack {
                    Button("Add selected (\(selectedSuggestions.count))") {
                        let chosen = model.subtaskSuggestions.filter {
                            selectedSuggestions.contains($0.title)
                        }
                        Task { await model.addSubtasks(chosen) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedSuggestions.isEmpty || model.isSaving)

                    Button("Dismiss") {
                        model.dismissSubtaskSuggestions()
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Spacing.cornerRadius)
                .fill(.quaternary.opacity(0.35))
        )
    }

    private func selectionBinding(_ title: String) -> Binding<Bool> {
        Binding(
            get: { selectedSuggestions.contains(title) },
            set: { isOn in
                if isOn {
                    selectedSuggestions.insert(title)
                } else {
                    selectedSuggestions.remove(title)
                }
            }
        )
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
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            onOpenAttachment?(attachment)
                        }
                        .help(openTooltip(attachment))

                    Spacer()

                    Button {
                        Task { await model.removeAttachment(attachment.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove attachment")
                    .disabled(model.isSaving)
                }
                .frame(height: DesignTokens.Spacing.rowHeight)
                .contextMenu {
                    Button("Open") { onOpenAttachment?(attachment) }
                    Button("Open With…") { onOpenAttachmentWith?(attachment) }
                    Divider()
                    Button("Quick Look") { onQuickLookAttachment?(attachment) }
                    Button("Reveal in Finder") { onRevealAttachment?(attachment) }
                }
            }
        }
    }

    @MainActor
    private func openTooltip(_ attachment: Attachment) -> String {
        if let app = defaultApplicationName?(attachment) {
            return "Double-click to open in \(app). Right-click for Open With."
        }
        return "Double-click to open. Right-click for Open With."
    }

    @MainActor
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sectionGap) {
            HStack {
                Text("Links")
                    .font(.headline)

                Spacer()

                if !model.linkCandidates.isEmpty {
                    Menu("Add link") {
                        Menu("Blocked by") {
                            ForEach(model.linkCandidates) { candidate in
                                Button(candidate.title) {
                                    Task { await model.addLink(to: candidate.id, kind: .blocks) }
                                }
                            }
                        }
                        Menu("Related") {
                            ForEach(model.linkCandidates) { candidate in
                                Button(candidate.title) {
                                    Task { await model.addLink(to: candidate.id, kind: .relatesTo) }
                                }
                            }
                        }
                    }
                    .disabled(model.isSaving)
                    .accessibilityLabel("Add a link")
                }
            }

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
    }

    /// The complete audit trail (FR-20): every create/edit/status/link/drop,
    /// with who, when, which app, and the file path or URL involved.
    @MainActor
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity")
                .font(.headline)

            ForEach(model.activity) { event in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: activitySymbol(event.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(event.summary)
                                .font(.callout)

                            Spacer()

                            Text(
                                event.occurredAt,
                                format: .dateTime.month(.abbreviated).day().hour().minute()
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            Text(event.actor)
                            if let app = event.sourceApp {
                                Text("via \(appDisplayName(app))")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(location)
                                .textSelection(.enabled)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(activityAccessibilityLabel(event))
            }
        }
    }

    private func activitySymbol(_ kind: ActivityEvent.Kind) -> String {
        switch kind {
        case .dropped, .attachmentAdded: return "paperclip"
        case .created: return "plus.circle"
        case .completed: return "checkmark.circle.fill"
        case .reopened: return "arrow.counterclockwise"
        case .deleted, .attachmentRemoved, .linkRemoved: return "trash"
        case .linkAdded: return "link"
        case .priorityChanged: return "exclamationmark.circle"
        case .scheduled: return "calendar"
        case .reminderSet: return "bell.fill"
        case .reminderCleared: return "bell.slash"
        case .reordered: return "arrow.up.arrow.down"
        case .reparented: return "arrow.triangle.branch"
        case .aiSuggested: return "sparkles"
        case .edited, .statusChanged, .other: return "pencil"
        }
    }

    private func appDisplayName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.apple.finder": return "Finder"
        case "com.apple.Safari": return "Safari"
        case "com.apple.mail": return "Mail"
        case "com.microsoft.Outlook": return "Outlook"
        case "com.microsoft.teams2", "com.microsoft.teams": return "Teams"
        case "com.apple.Preview": return "Preview"
        case "com.apple.Photos": return "Photos"
        default: return bundleId
        }
    }

    private func activityAccessibilityLabel(_ event: ActivityEvent) -> String {
        var parts = [event.summary, "by \(event.actor)"]
        if let app = event.sourceApp { parts.append("from \(appDisplayName(app))") }
        if let location = event.location, !location.isEmpty { parts.append(location) }
        parts.append(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
        return parts.joined(separator: ", ")
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
                .help("Mark this task done")
            }

            Button {
                Task { await model.commit() }
            } label: {
                Label("Save", systemImage: "checkmark.circle")
            }
            .help("Save changes now")
            .disabled(model.isSaving)

            Button("Move to tomorrow") {
                Task { await model.moveToTomorrow() }
            }
            .help("Reschedule to the next working day")

            Spacer()

            Button(role: .destructive) {
                Task { await model.delete() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete this task")
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
