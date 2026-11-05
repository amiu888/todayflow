import SwiftUI
import Foundation
import UniformTypeIdentifiers
import TodayFlowCore
import TodayFlowDesign

/// The working-tray strip: named staging areas for the tasks in progress.
/// Drop a task from the list (or another tray) onto a tray to add it; the trays
/// are views over tasks, not a separate list.
public struct TrayStripView: View {
    private let model: TodayViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingTray = false
    @State private var insertAfter: UUIDv7?
    @State private var newTrayName = ""
    @State private var renamingTray: UUIDv7?
    @State private var renameText = ""
    @State private var dropTargetID: UUIDv7?

    public init(model: TodayViewModel) {
        self.model = model
    }

    @MainActor
    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Working trays")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)

                Spacer()

                Button {
                    insertAfter = nil
                    newTrayName = ""
                    isAddingTray = true
                } label: {
                    Label("New tray", systemImage: "plus")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Palette.accent)
                .help("Add a new working tray")
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(model.trayColumns) { column in
                        trayCard(column)
                    }

                    addTrayCard
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        .alert("New working tray", isPresented: $isAddingTray) {
            TextField("Tray name", text: $newTrayName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = newTrayName
                let after = insertAfter
                Task { await model.addTray(name: name, after: after) }
            }
        } message: {
            Text("Give the tray a short name, such as “Now”, “Waiting”, or “Client A”.")
        }
        .alert(
            "Rename tray",
            isPresented: Binding(
                get: { renamingTray != nil },
                set: { if !$0 { renamingTray = nil } }
            )
        ) {
            TextField("Tray name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingTray = nil }
            Button("Rename") {
                if let id = renamingTray {
                    Task { await model.renameTray(id, to: renameText) }
                }
                renamingTray = nil
            }
        }
    }

    @MainActor
    private func trayColor(_ tray: WorkTray) -> Color {
        Color(
            hex: tray.colorHex
                ?? DesignTokens.TrayPalette.colorHex(at: tray.sortOrder)
        )
    }

    @MainActor
    private func trayCard(_ column: TodayViewModel.TrayColumn) -> some View {
        let tint = trayColor(column.tray)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: DesignTokens.TrayPalette.iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)

                Text(column.tray.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text("\(column.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)

                Menu {
                    Button("Rename…") {
                        renameText = column.tray.name
                        renamingTray = column.tray.id
                    }
                    Menu("Color") {
                        ForEach(DesignTokens.TrayPalette.colors, id: \.self) { hex in
                            Button {
                                Task {
                                    await model.setTrayColor(column.tray.id, colorHex: hex)
                                }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 8, height: 8)
                                    Text(hex)
                                    if hex == column.tray.colorHex {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                    Button("Insert tray after…") {
                        insertAfter = column.tray.id
                        newTrayName = ""
                        isAddingTray = true
                    }
                    Divider()
                    Button("Move left") {
                        Task { await model.moveTrayLeft(column.tray.id) }
                    }
                    Button("Move right") {
                        Task { await model.moveTrayRight(column.tray.id) }
                    }
                    Divider()
                    Button("Delete tray", role: .destructive) {
                        Task { await model.deleteTray(column.tray.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Tray actions")
                .accessibilityLabel("Actions for \(column.tray.name)")
            }

            if column.items.isEmpty {
                Text("Drop a task here")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                DesignTokens.Palette.hairline,
                                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                            )
                    )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(column.items) { item in
                            chip(item, trayId: column.tray.id)
                        }
                    }
                }
                .frame(maxHeight: 78)
            }
        }
        .padding(8)
        .frame(width: 190, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(tint)
                .frame(width: 26, height: 2)
                .padding(.top, 3)
        }
        .shadow(color: DesignTokens.Palette.shadow.opacity(0.5), radius: 6, y: 2)
        .contentShape(Rectangle())
        .onDrop(
            of: [.todayFlowWorkItem],
            isTargeted: Binding(
                get: { dropTargetID == column.tray.id },
                set: { targeted in
                    if targeted {
                        dropTargetID = column.tray.id
                    } else if dropTargetID == column.tray.id {
                        dropTargetID = nil
                    }
                }
            )
        ) { providers in
            Diagnostics.log(
                "tray",
                "drop on tray \(column.tray.name) providers=\(providers.count)"
            )
            guard let provider = providers.first else { return false }
            let trayId = column.tray.id
            Task { @MainActor in
                let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.todayFlowWorkItem.identifier,
                    options: nil
                )
                let string = (item as? String)
                    ?? (item as? NSString).map(String.init)
                guard let string, let uuid = UUID(uuidString: string) else { return }
                await model.addToTray(UUIDv7(uuid), trayId: trayId)
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    dropTargetID == column.tray.id
                        ? DesignTokens.Palette.accent
                        : Color.clear,
                    lineWidth: 2
                )
        )
        .accessibilityIdentifier("tray-\(column.tray.name)")
        .accessibilityLabel("\(column.tray.name) tray, \(column.items.count) tasks")
    }

    @MainActor
    private func chip(_ item: WorkItem, trayId: UUIDv7) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(PriorityColor.color(for: item.priority, in: colorScheme))
                .frame(width: 6, height: 6)

            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(DesignTokens.Palette.textPrimary)

            Spacer(minLength: 2)

            Button {
                Task { await model.removeFromTray(item.id, trayId: trayId) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from tray")
            .accessibilityLabel("Remove \(item.title) from tray")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.Palette.surfaceRaised)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.onOpenTask?(item.id)
        }
        .contextMenu {
            Button("Open") { model.onOpenTask?(item.id) }
            Button("Focus for 25 minutes") { model.onFocusTask?(item.id) }
            Divider()
            Button("Remove from tray") {
                Task { await model.removeFromTray(item.id, trayId: trayId) }
            }
        }
        .help(item.descriptionMd.isEmpty ? item.title : item.descriptionMd)
        .accessibilityIdentifier("tray-chip-\(item.title)")
        .draggable(WorkItemDragPayload(itemId: item.id))
    }

    @MainActor
    private var addTrayCard: some View {
        Button {
            insertAfter = nil
            newTrayName = ""
            isAddingTray = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                Text("New tray")
                    .font(.caption2)
            }
            .foregroundStyle(DesignTokens.Palette.accent)
            .frame(width: 90, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignTokens.Palette.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        DesignTokens.Palette.accent.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Add a working tray with a custom name")
        .accessibilityLabel("Add working tray")
    }
}
