import SwiftUI
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowDesign
#if canImport(AppKit)
import AppKit
#endif

public struct TaskRowView: View {
    public let model: TaskRowModel
    public let onToggle: @Sendable (UUIDv7) -> Void
    public let onQuickAction: @Sendable (UUIDv7, TaskRowQuickAction) -> Void
    public let motion: Motion

    /// Whether this row is the selected one (single tap; drives ⌥↑/⌥↓, FR-12).
    public let isSelected: Bool
    /// Single tap: select / deselect (FR-12).
    public let onSelect: @Sendable (UUIDv7) -> Void
    /// Drop of a dragged row: `(draggedId, targetId, insertBefore)`, FR-12.
    public let onMove: @Sendable (UUIDv7, UUIDv7, Bool) -> Void
    /// All trays, for the “Add to tray” context-menu fallback.
    public let allTrays: [WorkTray]
    public let onAddToTray: (@Sendable (UUIDv7, UUIDv7) -> Void)?
    /// Narrow-panel layout: the trailing metadata moves under the title so
    /// every control stays visible instead of being clipped.
    public let isCompact: Bool

    public init(
        model: TaskRowModel,
        onToggle: @escaping @Sendable (UUIDv7) -> Void,
        onQuickAction: @escaping @Sendable (UUIDv7, TaskRowQuickAction) -> Void,
        motion: Motion = Motion(preference: .full),
        isSelected: Bool = false,
        onSelect: @escaping @Sendable (UUIDv7) -> Void = { _ in },
        onMove: @escaping @Sendable (UUIDv7, UUIDv7, Bool) -> Void = { _, _, _ in },
        allTrays: [WorkTray] = [],
        onAddToTray: (@Sendable (UUIDv7, UUIDv7) -> Void)? = nil,
        isCompact: Bool = false
    ) {
        self.model = model
        self.onToggle = onToggle
        self.onQuickAction = onQuickAction
        self.motion = motion
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onMove = onMove
        self.allTrays = allTrays
        self.onAddToTray = onAddToTray
        self.isCompact = isCompact
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering: Bool = false
    @State private var showsAttachments = false
    @State private var attachmentHoverTask: Task<Void, Never>?
    @State private var isReorderTarget = false

    @MainActor
    public var body: some View {
        let dueTime = Self.formatDueTime(model.dueAt)

        Group {
            if isCompact {
                compactRow(dueTime: dueTime)
            } else {
                row(dueTime: dueTime)
            }
        }
        .frame(minHeight: DesignTokens.Spacing.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(
                    cornerRadius: DesignTokens.Spacing.cornerRadius,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? DesignTokens.Palette.accent.opacity(0.18)
                        : (model.isDueSoon
                            ? DesignTokens.Palette.warning.opacity(0.12)
                            : (isHovering
                                ? DesignTokens.Palette.accent.opacity(0.09)
                                : DesignTokens.Palette.surface.opacity(0.55)))
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.Spacing.cornerRadius,
                        style: .continuous
                    )
                    .stroke(
                        isReorderTarget
                            ? DesignTokens.Palette.accent
                            : (isSelected ? DesignTokens.Palette.accent.opacity(0.5) : Color.clear),
                        lineWidth: isReorderTarget ? 2 : 1
                    )
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(model.id)
                // A click opens the detail view; reordering is drag or the
                // explicit move actions.
                onQuickAction(model.id, .open)
            }
            .onHover { isHovering = $0 }
            .overlay(alignment: .trailing) {
                if isHovering && !isCompact {
                    quickActions
                }
            }
            // Drag the row anywhere to reorder it or drop it on a tray. A
            // click still opens the task because SwiftUI starts the drag only
            // after the pointer moves.
            .onDrag {
                WorkItemDragPayload.itemProvider(for: model.id)
            }
            .onDrop(
                of: [.todayFlowWorkItem],
                delegate: TaskRowDropDelegate(
                    targetId: model.id,
                    isTargeted: $isReorderTarget,
                    onMove: onMove
                )
            )
            .contextMenu {
                Button("Open") { onQuickAction(model.id, .open) }
                Button("Focus for 25 minutes") { onQuickAction(model.id, .focus) }
                if !allTrays.isEmpty, let onAddToTray {
                    Menu("Add to tray") {
                        ForEach(allTrays) { tray in
                            Button(tray.name) {
                                onAddToTray(model.id, tray.id)
                            }
                        }
                    }
                }
                Divider()
                Button("Move up") { onQuickAction(model.id, .moveUp) }
                Button("Move down") { onQuickAction(model.id, .moveDown) }
                Menu("Priority") {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Button(priority.label) {
                            onQuickAction(model.id, .setPriority(priority))
                        }
                    }
                }
                Button("Move to tomorrow") {
                    onQuickAction(model.id, .moveToTomorrow)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-row-\(model.title)")
    }

    @MainActor
    private func row(dueTime: String) -> some View {
        HStack(spacing: 8) {
            parentColorBar
            dragHandle
            completionControl
            priorityPill
            titleBlock(dueTime: dueTime, compact: false)
            trayBadges
            attachmentCluster
            moveControls
        }
    }

    @MainActor
    private func compactRow(dueTime: String) -> some View {
        HStack(spacing: 8) {
            parentColorBar
            dragHandle
            completionControl
            priorityPill
            titleBlock(dueTime: dueTime, compact: true)
        }
    }

    @ViewBuilder
    private var parentColorBar: some View {
        if let parentColorHex = model.parentColorHex {
            Rectangle()
                .fill(Color(hex: parentColorHex))
                .frame(width: 3)
        }
    }

    @MainActor
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.7))
            .frame(width: 14, height: 24)
            .contentShape(Rectangle())
            .help("Drag to reorder or into a tray")
            .accessibilityLabel("Drag \(model.title)")
            .accessibilityIdentifier("drag-handle-\(model.title)")
    }

    @MainActor
    private func titleBlock(dueTime: String, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(model.isDone)
                .foregroundStyle(model.isDone ? Color.secondary : Color.primary)
                .accessibilityLabel(accessibilityLabel(dueTime: dueTime))
                .help(model.descriptionPreview ?? "Open “\(model.title)”")

            if compact {
                HStack(spacing: 4) {
                    dueLine(dueTime)
                    trayBadges
                    attachmentCluster
                    Spacer(minLength: 0)
                    compactMoveControls
                }
            } else {
                dueLine(dueTime)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .overlay {
            TaskDragSource(
                itemId: model.id,
                title: model.title,
                tooltip: model.descriptionPreview ?? "Open “\(model.title)”",
                onClick: {
                    onSelect(model.id)
                    onQuickAction(model.id, .open)
                },
                menuActions: dragMenuActions
            )
        }
    }

    @MainActor
    private func dueLine(_ dueTime: String) -> some View {
        HStack(spacing: 4) {
            if model.isDueSoon {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.warning)
                    .help("Due soon: \(dueTime)")
                    .accessibilityHidden(true)
            }

            Text(dueTime)
                .font(.system(size: 10))
                .foregroundStyle(
                    model.isOverdue
                        ? DesignTokens.Palette.danger
                        : DesignTokens.Palette.textSecondary
                )
                .help(model.isOverdue ? "Overdue — was due \(dueTime)" : "Due at \(dueTime)")

            if model.isBlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.secondary)
                    .help("Blocked by an unfinished task")
            }
        }
    }

    @ViewBuilder
    private var trayBadges: some View {
        ForEach(model.trays.prefix(2)) { tray in
            Image(systemName: DesignTokens.TrayPalette.iconName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(hex: tray.colorHex))
                .help("Tray: \(tray.name)")
                .accessibilityLabel("In tray \(tray.name)")
        }

        if model.trays.count > 2 {
            Text("+\(model.trays.count - 2)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .help(model.trays.dropFirst(2).map(\.name).joined(separator: ", "))
        }
    }

    @MainActor
    private var moveControls: some View {
        VStack(spacing: 0) {
            moveButton(up: true)
            moveButton(up: false)
        }
        .fixedSize()
    }

    @MainActor
    private var compactMoveControls: some View {
        HStack(spacing: 2) {
            moveButton(up: true, compact: true)
            moveButton(up: false, compact: true)
        }
    }

    @MainActor
    private func moveButton(up: Bool, compact: Bool = false) -> some View {
        Button {
            onQuickAction(model.id, up ? .moveUp : .moveDown)
        } label: {
            Image(systemName: up ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .frame(width: compact ? 14 : 18, height: compact ? 14 : 16)
        }
        .buttonStyle(.plain)
        .help(up ? "Move up" : "Move down")
        .accessibilityLabel(up ? "Move \(model.title) up" : "Move \(model.title) down")
        .accessibilityIdentifier(up ? "move-up-\(model.title)" : "move-down-\(model.title)")
    }

    @ViewBuilder
    private var actionMenuContent: some View {
        Button("Open") { onQuickAction(model.id, .open) }
        Button("Focus for 25 minutes") { onQuickAction(model.id, .focus) }
        if !allTrays.isEmpty, let onAddToTray {
            Menu("Add to tray") {
                ForEach(allTrays) { tray in
                    Button(tray.name) {
                        onAddToTray(model.id, tray.id)
                    }
                }
            }
        }
        Divider()
        Button("Move up") { onQuickAction(model.id, .moveUp) }
        Button("Move down") { onQuickAction(model.id, .moveDown) }
        Menu("Priority") {
            ForEach(Priority.allCases, id: \.self) { priority in
                Button(priority.label) {
                    onQuickAction(model.id, .setPriority(priority))
                }
            }
        }
        Button("Move to tomorrow") {
            onQuickAction(model.id, .moveToTomorrow)
        }
    }

    @MainActor
    private var completionControl: some View {
        let id = model.id
        let toggle = onToggle
        let isDone = model.isDone
        let priority = model.priority
        let scheme = colorScheme
        let hasChain = model.hasChainBelow
        let animation = checkmarkAnimation

        return Button {
            toggle(id)
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isDone ? PriorityColor.color(for: priority, in: scheme) : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .animation(animation, value: isDone)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isDone ? "Reopen task" : "Mark done")
        .overlay {
            if hasChain {
                Rectangle()
                    .foregroundStyle(.quaternary)
                    .frame(width: 1.5, height: 8)
                    .offset(y: 15)
                    .allowsHitTesting(false)
            }
        }
    }

    @MainActor
    private var attachmentCluster: some View {
        let scheme = colorScheme
        let hints = Array(model.attachments.prefix(3))
        let extra = model.attachmentCount - 3

        return HStack(spacing: 4) {
            ForEach(hints, id: \.self) { hint in
                attachmentIcon(hint, scheme: scheme)
            }

            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .help(attachmentTooltip)
        .onHover { hovering in
            attachmentHoverTask?.cancel()
            if hovering {
                showsAttachments = true
            } else {
                attachmentHoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    showsAttachments = false
                }
            }
        }
        .popover(isPresented: $showsAttachments, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Attachments")
                    .font(.caption.weight(.semibold))
                ForEach(model.allAttachments, id: \.self) { hint in
                    HStack(spacing: 6) {
                        attachmentIcon(hint, scheme: scheme)
                        Text(hint.displayName)
                            .font(.caption)
                            .lineLimit(1)
                        if let app = hint.sourceApp {
                            Text("· \(shortAppName(app))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .frame(minWidth: 180, maxWidth: 300, alignment: .leading)
        }
    }

    @MainActor
    @ViewBuilder
    private func attachmentIcon(
        _ hint: TaskRowModel.AttachmentHint,
        scheme: ColorScheme
    ) -> some View {
        #if canImport(AppKit)
        if let app = hint.sourceApp,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app)
        {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .frame(width: 13, height: 13)
        } else {
            kindIcon(hint, scheme: scheme)
        }
        #else
        kindIcon(hint, scheme: scheme)
        #endif
    }

    @MainActor
    private func kindIcon(
        _ hint: TaskRowModel.AttachmentHint,
        scheme: ColorScheme
    ) -> some View {
        let style = AttachmentIconStyle.style(
            uti: nil,
            displayName: hint.displayName,
            kind: hint.kind
        )
        return Image(systemName: style.symbolName)
            .font(.system(size: 12))
            .foregroundStyle(style.tint(in: scheme))
    }

    private var attachmentTooltip: String {
        guard !model.allAttachments.isEmpty else { return "No attachments" }
        return model.allAttachments
            .map { hint in
                if let app = hint.sourceApp {
                    return "\(hint.displayName) (\(shortAppName(app)))"
                }
                return hint.displayName
            }
            .joined(separator: "\n")
    }

    private func shortAppName(_ bundleId: String) -> String {
        switch bundleId {
        case "com.apple.finder": return "Finder"
        case "com.apple.Safari": return "Safari"
        case "com.apple.mail": return "Mail"
        case "com.microsoft.Outlook": return "Outlook"
        case "com.microsoft.teams2", "com.microsoft.teams": return "Teams"
        case "com.apple.AddressBook", "com.apple.contacts", "contacts": return "Contacts"
        case "com.apple.Preview": return "Preview"
        default: return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        }
    }

    /// The always-visible, compact priority control. Priority is a frequent
    /// action, so it should not require hovering (which also used to stretch a
    /// popup button across the row and block dragging).
    @MainActor
    private var priorityPill: some View {
        let id = model.id
        let quick = onQuickAction
        let priority = model.priority
        let scheme = colorScheme
        let tint = PriorityColor.color(for: priority, in: scheme)

        return Menu {
            ForEach(Priority.allCases, id: \.self) { option in
                Button {
                    quick(id, .setPriority(option))
                } label: {
                    if option == priority {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text("P\(priority.rawValue)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(scheme == .dark ? 0.16 : 0.12))
            )
            .overlay(
                Capsule().stroke(tint.opacity(0.45), lineWidth: 0.75)
            )
            .frame(minWidth: 28)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Priority: \(priority.label) — click to change")
        .accessibilityLabel("Priority: \(priority.label)")
        .accessibilityIdentifier("row-priority-\(model.title)")
    }

    @MainActor
    private var quickActions: some View {
        let id = model.id
        let quick = onQuickAction

        return HStack(spacing: 2) {
            if !allTrays.isEmpty, let onAddToTray {
                Menu {
                    ForEach(allTrays) { tray in
                        Button(tray.name) {
                            onAddToTray(id, tray.id)
                        }
                    }
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add to tray")
                .accessibilityLabel("Add to tray")
                .accessibilityIdentifier("row-tray-menu-\(model.title)")
            }

            Button {
                quick(id, .open)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help("Open details")
        }
        .padding(4)
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: DesignTokens.Spacing.cornerRadius,
                style: .continuous
            )
        )
        .padding(.trailing, 8)
    }

    private var checkmarkAnimation: Animation? {
        motion.duration(for: .checkmark).map { .easeInOut(duration: $0) }
    }

    private static func formatDueTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private struct TaskRowDropDelegate: DropDelegate {
        let targetId: UUIDv7
        let isTargeted: Binding<Bool>
        let onMove: @Sendable (UUIDv7, UUIDv7, Bool) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.todayFlowWorkItem])
        }

        func dropEntered(info: DropInfo) {
            isTargeted.wrappedValue = true
        }

        func dropExited(info: DropInfo) {
            isTargeted.wrappedValue = false
        }

        func performDrop(info: DropInfo) -> Bool {
            isTargeted.wrappedValue = false

            let before = info.location.y < DesignTokens.Spacing.rowHeight / 2
            let target = targetId
            let move = onMove

            let snapshotted = WorkItemDragPayload.loadFromDragPasteboard()
            if let payload = snapshotted.first(where: { $0.itemId != target }) {
                move(payload.itemId, target, before)
                return true
            }

            guard let provider = info.itemProviders(for: [.todayFlowWorkItem]).first
            else { return false }

            let box = WorkItemDragPayload.ProviderBox(provider)
            Task { @MainActor in
                guard let payload = await WorkItemDragPayload.load(from: box.provider),
                      payload.itemId != target
                else { return }
                move(payload.itemId, target, before)
            }
            return true
        }
    }

    @MainActor
    private var dragMenuActions: [TaskDragSource.MenuAction] {
        let id = model.id
        let quick = onQuickAction
        var actions: [TaskDragSource.MenuAction] = [
            .init("Open") { quick(id, .open) },
            .init("Focus for 25 minutes") { quick(id, .focus) },
        ]

        if !allTrays.isEmpty, let onAddToTray {
            actions.append(.separator)
            for tray in allTrays {
                actions.append(.init("Add to \(tray.name)") {
                    onAddToTray(id, tray.id)
                })
            }
        }

        actions.append(.separator)
        actions.append(.init("Move up") { quick(id, .moveUp) })
        actions.append(.init("Move down") { quick(id, .moveDown) })
        actions.append(.init("Move to tomorrow") { quick(id, .moveToTomorrow) })

        actions.append(.separator)
        for priority in Priority.allCases {
            actions.append(.init("Priority: \(priority.label)") {
                quick(id, .setPriority(priority))
            })
        }

        return actions
    }

    private func accessibilityLabel(dueTime: String) -> String {
        var parts: [String] = []

        if !model.title.isEmpty {
            parts.append(model.title)
        }

        if model.isDone {
            parts.append("done")
        } else if model.isDueSoon {
            parts.append("due soon")
        }

        parts.append(model.priority.label)

        if model.isOverdue {
            parts.append("overdue")
        }

        parts.append("due at \(dueTime)")

        return parts.joined(separator: ", ")
    }
}
