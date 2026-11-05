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

    public init(
        model: TaskRowModel,
        onToggle: @escaping @Sendable (UUIDv7) -> Void,
        onQuickAction: @escaping @Sendable (UUIDv7, TaskRowQuickAction) -> Void,
        motion: Motion = Motion(preference: .full),
        isSelected: Bool = false,
        onSelect: @escaping @Sendable (UUIDv7) -> Void = { _ in },
        onMove: @escaping @Sendable (UUIDv7, UUIDv7, Bool) -> Void = { _, _, _ in },
        allTrays: [WorkTray] = [],
        onAddToTray: (@Sendable (UUIDv7, UUIDv7) -> Void)? = nil
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

        row(dueTime: dueTime)
            .frame(height: DesignTokens.Spacing.rowHeight)
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
                if isHovering {
                    quickActions
                }
            }
            // The small grip at the leading edge is the drag source; the row
            // itself stays clickable for opening details and moving with the
            // chevrons.
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
            if let parentColorHex = model.parentColorHex {
                Rectangle()
                    .fill(Color(hex: parentColorHex))
                    .frame(width: 3)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.textSecondary.opacity(0.7))
                .frame(width: 14, height: 24)
                .contentShape(Rectangle())
                .draggable(WorkItemDragPayload(itemId: model.id))
                .help("Drag to reorder or into a tray")
                .accessibilityLabel("Drag \(model.title)")
                .accessibilityIdentifier("drag-handle-\(model.title)")

            completionControl

            Circle()
                .fill(PriorityColor.color(for: model.priority, in: colorScheme))
                .frame(width: 8, height: 8)
                .help("Priority: \(model.priority.label)")

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(model.isDone)
                    .foregroundStyle(model.isDone ? Color.secondary : Color.primary)
                    .accessibilityLabel(accessibilityLabel(dueTime: dueTime))
                    .help(model.descriptionPreview ?? "Open “\(model.title)”")

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
            .frame(maxWidth: .infinity, alignment: .leading)

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

            attachmentCluster

            VStack(spacing: 0) {
                Button {
                    onQuickAction(model.id, .moveUp)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .frame(width: 18, height: 16)
                }
                .buttonStyle(.plain)
                .help("Move up")
                .accessibilityLabel("Move \(model.title) up")
                .accessibilityIdentifier("move-up-\(model.title)")

                Button {
                    onQuickAction(model.id, .moveDown)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .frame(width: 18, height: 16)
                }
                .buttonStyle(.plain)
                .help("Move down")
                .accessibilityLabel("Move \(model.title) down")
                .accessibilityIdentifier("move-down-\(model.title)")
            }
            .fixedSize()
        }
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
        case "com.apple.Preview": return "Preview"
        default: return bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        }
    }

    @MainActor
    private var quickActions: some View {
        let id = model.id
        let quick = onQuickAction
        let priority = model.priority
        let scheme = colorScheme

        return HStack(spacing: 4) {
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button(priority.label) {
                        quick(id, .setPriority(priority))
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Circle()
                        .fill(PriorityColor.color(for: priority, in: scheme))
                        .frame(width: 8, height: 8)

                    Text("priority")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
            }
            .help("Change priority")

            Button {
                quick(id, .focus)
            } label: {
                Image(systemName: "scope")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help("Focus for 25 minutes")

            Button {
                quick(id, .moveToTomorrow)
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
            .help("Move to tomorrow")

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
            guard let provider = info.itemProviders(for: [.todayFlowWorkItem]).first
            else { return false }

            let before = info.location.y < DesignTokens.Spacing.rowHeight / 2
            let target = targetId
            let move = onMove
            Task { @MainActor in
                guard let string = try? await provider.loadItem(
                    forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
                    options: nil
                ) as? String,
                    let uuid = UUID(uuidString: string),
                    UUIDv7(uuid) != target
                else { return }
                move(UUIDv7(uuid), target, before)
            }
            return true
        }
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
