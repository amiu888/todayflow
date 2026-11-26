#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowDesign
import TodayFlowFeatures

/// Working trays on the iPhone: the same trays as the Mac (they sync), shown
/// as a strip of chips on Today. A tray holds the tasks in play; a task sits
/// in at most one tray. All rules come from the Mac's `TodayViewModel`.
struct PhoneTrayStrip: View {
    @Bindable var model: TodayViewModel
    var onOpen: (UUIDv7) -> Void

    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.trays.sorted { $0.sortOrder < $1.sortOrder }) { tray in
                    Button { onOpen(tray.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: DesignTokens.TrayPalette.iconName)
                                .foregroundStyle(trayColor(tray))
                            Text(tray.name).lineLimit(1)
                            Text("\(model.trayItems(trayId: tray.id).count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(trayColor(tray).opacity(0.14), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tray.name) tray, \(model.trayItems(trayId: tray.id).count) tasks")
                }
                Button {
                    newName = ""
                    naming = true
                } label: {
                    Label("New Tray", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .padding(9)
                        .background(Color.secondary.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New tray")
            }
        }
        .alert("New Tray", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await model.addTray(name: newName) } }
        } message: {
            Text("Trays hold the tasks you're working on. They appear on your Mac too.")
        }
    }

    private func trayColor(_ tray: WorkTray) -> Color {
        Color(hex: tray.colorHex ?? DesignTokens.TrayPalette.colorHex(at: tray.sortOrder))
    }
}

/// The Trays tab: every tray with its count and first tasks. Pull down to
/// sync now; tap a tray to open it.
struct PhoneTraysTab: View {
    @Bindable var model: TodayViewModel
    let environment: PhoneEnvironment
    var sync: SyncController?

    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(model.trays.sorted { $0.sortOrder < $1.sortOrder }) { tray in
                let items = model.trayItems(trayId: tray.id)
                NavigationLink(value: PhoneTrayRoute(id: tray.id)) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: DesignTokens.TrayPalette.iconName)
                            .font(.title3)
                            .foregroundStyle(color(tray))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(tray.name).font(.headline).lineLimit(1)
                                Spacer()
                                Text("\(items.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if items.isEmpty {
                                Text("Empty").font(.subheadline).foregroundStyle(.tertiary)
                            } else {
                                ForEach(items.prefix(3)) { item in
                                    Text(item.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .strikethrough(item.status.isTerminal)
                                        .lineLimit(1)
                                }
                                if items.count > 3 {
                                    Text("and \(items.count - 3) more").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("\(tray.name) tray, \(items.count) tasks")
            }
            Section {
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle("Trays")
        .navigationDestination(for: PhoneTrayRoute.self) { route in
            PhoneTrayDetailView(model: model, trayId: route.id, environment: environment)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Tray", systemImage: "plus") {
                    newName = ""
                    naming = true
                }
            }
        }
        .refreshable {
            await sync?.syncNow()
            await model.reloadTrays()
            await model.load()
        }
        .task {
            await model.reloadTrays()
            await model.load()
        }
        .alert("New Tray", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await model.addTray(name: newName) } }
        } message: {
            Text("Trays hold the tasks you're working on. They appear on your Mac too.")
        }
    }

    private var footer: String {
        if sync?.snapshot.isPaired == true {
            return "Trays sync with your Mac. Pull down to check for changes. Add a task from Today: touch and hold it, then choose Add to Tray."
        }
        return "Pair with your server in Settings ▸ Sync to see your Mac's trays here."
    }

    private func color(_ tray: WorkTray) -> Color {
        Color(hex: tray.colorHex ?? DesignTokens.TrayPalette.colorHex(at: tray.sortOrder))
    }
}

/// One tray's tasks: open, reorder, remove; rename, recolor or delete the tray.
struct PhoneTrayDetailView: View {
    @Bindable var model: TodayViewModel
    let trayId: UUIDv7
    let environment: PhoneEnvironment

    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let tray = model.tray(id: trayId) {
                content(tray)
            } else {
                ContentUnavailableView("Tray deleted", systemImage: DesignTokens.TrayPalette.iconName)
            }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private func content(_ tray: WorkTray) -> some View {
        let items = model.trayItems(trayId: trayId)
        List {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Empty tray", systemImage: DesignTokens.TrayPalette.iconName)
                } description: {
                    Text("On Today, touch and hold a task, then choose Add to Tray.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                NavigationLink {
                    PhoneTaskDestination(id: item.id, environment: environment)
                } label: {
                    PhoneTrayItemRow(item: item)
                }
                .swipeActions {
                    Button("Remove", systemImage: "tray.and.arrow.up", role: .destructive) {
                        Task { await model.removeFromTray(item.id, trayId: trayId) }
                    }
                }
                .contextMenu {
                    Button("Complete", systemImage: "checkmark.circle") { Task { await model.toggle(item.id) } }
                    let others = model.trays.filter { $0.id != trayId }
                    if !others.isEmpty {
                        Menu("Move to Tray", systemImage: "tray.2") {
                            ForEach(others) { other in
                                Button(other.name) { Task { await model.moveToTray(item.id, from: trayId, to: other.id) } }
                            }
                        }
                    }
                    Button("Remove from Tray", systemImage: "tray.and.arrow.up", role: .destructive) {
                        Task { await model.removeFromTray(item.id, trayId: trayId) }
                    }
                }
            }
            .onMove { from, to in
                guard let source = from.first else { return }
                let steps = to > source ? to - source - 1 : to - source
                let id = items[source].id
                Task {
                    for _ in 0..<abs(steps) {
                        if steps > 0 { await model.moveTrayItemDown(id, trayId: trayId) }
                        else { await model.moveTrayItemUp(id, trayId: trayId) }
                    }
                }
            }
        }
        .navigationTitle(tray.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    EditButton()
                    Button("Rename…", systemImage: "pencil") {
                        newName = tray.name
                        renaming = true
                    }
                    Menu("Color", systemImage: "paintpalette") {
                        ForEach(Array(DesignTokens.TrayPalette.colors.enumerated()), id: \.offset) { index, hex in
                            Button(DesignTokens.TrayPalette.names[index % DesignTokens.TrayPalette.names.count]) {
                                Task { await model.setTrayColor(trayId, colorHex: hex) }
                            }
                        }
                    }
                    Divider()
                    Button("Delete Tray…", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("Tray", systemImage: "ellipsis")
                }
            }
        }
        .alert("Rename Tray", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await model.renameTray(trayId, to: newName) } }
        }
        .confirmationDialog("Delete “\(tray.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Tray", role: .destructive) {
                Task {
                    await model.deleteTray(trayId)
                    dismiss()
                }
            }
        } message: {
            Text("The tasks stay; only the tray goes, on all your devices.")
        }
    }
}

private struct PhoneTrayItemRow: View {
    let item: WorkItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.status.isTerminal ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.status.isTerminal ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.status.isTerminal)
                    .lineLimit(2)
                Text(item.endAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.caption)
                    .foregroundStyle(item.endAt < .now && !item.status.isTerminal ? .red : .secondary)
            }
            Spacer()
            Text(item.priority.shortLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

/// Context-menu entries for a task on Today: add to a tray, or remove it.
struct PhoneTrayMenu: View {
    @Bindable var model: TodayViewModel
    let itemId: UUIDv7

    var body: some View {
        let current = model.trays.first { $0.itemIds.contains(itemId) }
        Menu(current == nil ? "Add to Tray" : "Move to Tray", systemImage: DesignTokens.TrayPalette.iconName) {
            ForEach(model.trays.sorted { $0.sortOrder < $1.sortOrder }) { tray in
                Button {
                    Task { await model.addToTray(itemId, trayId: tray.id) }
                } label: {
                    if tray.id == current?.id { Label(tray.name, systemImage: "checkmark") } else { Text(tray.name) }
                }
                .disabled(tray.id == current?.id)
            }
        }
        if let current {
            Button("Remove from \(current.name)", systemImage: "tray.and.arrow.up") {
                Task { await model.removeFromTray(itemId, trayId: current.id) }
            }
        }
    }
}
#endif
