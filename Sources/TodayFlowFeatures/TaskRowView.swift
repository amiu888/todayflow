import SwiftUI
import TodayFlowCore
import TodayFlowDesign

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

    public init(
        model: TaskRowModel,
        onToggle: @escaping @Sendable (UUIDv7) -> Void,
        onQuickAction: @escaping @Sendable (UUIDv7, TaskRowQuickAction) -> Void,
        motion: Motion = Motion(preference: .full),
        isSelected: Bool = false,
        onSelect: @escaping @Sendable (UUIDv7) -> Void = { _ in },
        onMove: @escaping @Sendable (UUIDv7, UUIDv7, Bool) -> Void = { _, _, _ in }
    ) {
        self.model = model
        self.onToggle = onToggle
        self.onQuickAction = onQuickAction
        self.motion = motion
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onMove = onMove
    }

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering: Bool = false

    @MainActor
    public var body: some View {
        let dueTime = Self.formatDueTime(model.dueAt)

        row(dueTime: dueTime)
            .frame(height: DesignTokens.Spacing.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(
                        cornerRadius: DesignTokens.Spacing.cornerRadius,
                        style: .continuous
                    )
                    .fill(Color.accentColor.opacity(0.15))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(model.id) }
            .onTapGesture(count: 2) { onQuickAction(model.id, .open) }
            .onHover { isHovering = $0 }
            .overlay(alignment: .trailing) {
                if isHovering {
                    quickActions
                }
            }
            // Drag to reorder (FR-12). The FR-30 drop popover (a choice of
            // "move / reparent / complete") is a later refinement; today a
            // drop is always a reorder relative to the target row.
            .draggable(WorkItemDragPayload(itemId: model.id))
            .dropDestination(for: WorkItemDragPayload.self) { payloads, location in
                guard let payload = payloads.first, payload.itemId != model.id else {
                    return false
                }
                let isBefore = location.y < DesignTokens.Spacing.rowHeight / 2
                onMove(payload.itemId, model.id, isBefore)
                return true
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(dueTime: dueTime))
    }

    @MainActor
    private func row(dueTime: String) -> some View {
        HStack(spacing: 8) {
            if let parentColorHex = model.parentColorHex {
                Rectangle()
                    .fill(Color(hex: parentColorHex))
                    .frame(width: 3)
            }

            completionControl

            Circle()
                .fill(PriorityColor.color(for: model.priority, in: colorScheme))
                .frame(width: 8, height: 8)

            Text(model.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .strikethrough(model.isDone)
                .foregroundStyle(model.isDone ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.isBlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }

            attachmentCluster

            Text(dueTime)
                .font(.system(size: 12))
                .foregroundStyle(model.isOverdue ? Color(hex: "#d03b3b") : Color.secondary)
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
                let style = AttachmentIconStyle.style(
                    uti: nil,
                    displayName: hint.displayName,
                    kind: hint.kind
                )

                Image(systemName: style.symbolName)
                    .font(.system(size: 12))
                    .foregroundStyle(style.tint(in: scheme))
            }

            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
            }
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

            Button {
                quick(id, .moveToTomorrow)
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)

            Button {
                quick(id, .open)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary)
            }
            .buttonStyle(.plain)
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

    private func accessibilityLabel(dueTime: String) -> String {
        var parts: [String] = []

        if !model.title.isEmpty {
            parts.append(model.title)
        }

        if model.isDone {
            parts.append("done")
        }

        parts.append(model.priority.label)

        if model.isOverdue {
            parts.append("overdue")
        }

        parts.append("due at \(dueTime)")

        return parts.joined(separator: ", ")
    }
}
