import SwiftUI
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowDesign

/// The full tray window: every task in a tray, with reordering, removal, and
/// drag/drop between trays. Supports an unlimited number of items.
public struct TrayDetailView: View {
    private let model: TodayViewModel
    private let trayId: UUIDv7

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false

    public init(model: TodayViewModel, trayId: UUIDv7) {
        self.model = model
        self.trayId = trayId
    }

    @MainActor
    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 380, minHeight: 420)
        .background(DesignTokens.Palette.background)
        .overlay(alignment: .top) { WindowDragGrabber() }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DesignTokens.Palette.accent, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [.todayFlowWorkItem],
            isTargeted: $isDropTargeted
        ) { providers in
            drop(providers)
        }
        .tint(DesignTokens.Palette.accent)
    }

    @MainActor
    private var tray: WorkTray? {
        model.tray(id: trayId)
    }

    @MainActor
    private var items: [WorkItem] {
        model.trayItems(trayId: trayId)
    }

    @MainActor
    private var header: some View {
        let tint = Color(
            hex: tray?.colorHex
                ?? DesignTokens.TrayPalette.colorHex(at: tray?.sortOrder ?? 0)
        )

        return HStack(spacing: 10) {
            Image(systemName: DesignTokens.TrayPalette.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(tray?.name ?? "Tray")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(DesignTokens.Palette.textPrimary)
                Text("\(items.count) task\(items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            Spacer()

            if let tray {
                Menu {
                    ForEach(DesignTokens.TrayPalette.colors, id: \.self) { hex in
                        Button {
                            Task { await model.setTrayColor(tray.id, colorHex: hex) }
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: hex)).frame(width: 8, height: 8)
                                Text(hex)
                                if hex == tray.colorHex { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.caption)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Change tray color")
            }
        }
        .padding(16)
    }

    @MainActor
    @ViewBuilder
    private var content: some View {
        if tray == nil {
            VStack(spacing: 8) {
                Text("This tray no longer exists.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: DesignTokens.TrayPalette.iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Drop tasks here")
                    .font(.body.weight(.medium))
                Text("Drag tasks from Today or another tray. There is no limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, index: index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    @MainActor
    private func row(_ item: WorkItem, index: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PriorityColor.color(for: item.priority, in: colorScheme))
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.callout)
                    .lineLimit(1)
                    .accessibilityIdentifier("tray-window-row-\(item.title)")
                Text(item.endAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .contentShape(Rectangle())
            .overlay {
                TaskDragSource(
                    itemId: item.id,
                    sourceTray: trayId,
                    title: item.title,
                    tooltip: item.descriptionMd.isEmpty
                        ? item.title
                        : item.descriptionMd,
                    onClick: { model.onOpenTask?(item.id) },
                    menuActions: trayMenuActions(for: item)
                )
            }

            Spacer()

            Button {
                model.onOpenTask?(item.id)
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open task")

            Button {
                Task { await model.moveTrayItemUp(item.id, trayId: trayId) }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("Move up in tray")
            .accessibilityIdentifier("tray-window-up-\(item.title)")

            Button {
                Task { await model.moveTrayItemDown(item.id, trayId: trayId) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(index == items.count - 1)
            .help("Move down in tray")
            .accessibilityIdentifier("tray-window-down-\(item.title)")

            Button {
                Task { await model.removeFromTray(item.id, trayId: trayId) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from tray")
            .accessibilityIdentifier("tray-window-remove-\(item.title)")
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Palette.surface.opacity(0.7))
        )
        .contentShape(Rectangle())
        .onDrag {
            WorkItemDragPayload.itemProvider(for: item.id, sourceTray: trayId)
        }
        .contextMenu {
            Button("Open") { model.onOpenTask?(item.id) }
            Divider()
            Button("Move up") {
                Task { await model.moveTrayItemUp(item.id, trayId: trayId) }
            }
            Button("Move down") {
                Task { await model.moveTrayItemDown(item.id, trayId: trayId) }
            }
            let otherTrays = model.trays.filter { $0.id != trayId }
            if !otherTrays.isEmpty {
                Menu("Move to tray") {
                    ForEach(otherTrays) { other in
                        Button(other.name) {
                            Task {
                                await model.moveToTray(
                                    item.id,
                                    from: trayId,
                                    to: other.id
                                )
                            }
                        }
                    }
                }
            }
            Button("Remove from tray") {
                Task { await model.removeFromTray(item.id, trayId: trayId) }
            }
        }
    }

    @MainActor
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let snapshotted = WorkItemDragPayload.loadFromDragPasteboard()
        Diagnostics.log(
            "tray",
            "window drop tray=\(trayId) providers=\(providers.count) snapshot=\(snapshotted.count)"
        )
        if !snapshotted.isEmpty {
            apply(snapshotted)
            return true
        }

        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadItem(
                forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
                options: nil
            ) { item, _ in
                guard let payload = WorkItemDragPayload.payload(from: item) else {
                    return
                }
                Task { @MainActor in
                    apply([payload])
                }
            }
        }
        return true
    }

    @MainActor
    private func trayMenuActions(for item: WorkItem) -> [TaskDragSource.MenuAction] {
        var actions: [TaskDragSource.MenuAction] = [
            .init("Open") { model.onOpenTask?(item.id) },
            .separator,
        ]
        for other in model.trays where other.id != trayId {
            actions.append(.init("Move to \(other.name)") {
                Task {
                    await model.moveToTray(
                        item.id,
                        from: trayId,
                        to: other.id
                    )
                }
            })
        }
        actions.append(.separator)
        actions.append(.init("Remove from tray") {
            Task { await model.removeFromTray(item.id, trayId: trayId) }
        })
        return actions
    }

    @MainActor
    private func apply(_ payloads: [WorkItemDragPayload]) {
        Task { @MainActor in
            await model.applyDrop(payloads, to: trayId)
        }
    }
}
