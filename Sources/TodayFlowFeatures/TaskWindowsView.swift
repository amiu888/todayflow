import SwiftUI
import TodayFlowCore
import TodayFlowDesign

/// What the Task Windows switcher shows; the Mac app keeps it up to date.
@MainActor
@Observable
public final class TaskWindowsModel {
    /// Open task windows in the current order (first = front of the stack).
    public var entries: [TaskWindowEntry] = []
    public var layout: TaskWindowLayout = .free
    public var order: TaskWindowOrder = .priority
    /// The task window in front, if any.
    public var activeId: UUIDv7?
    public var selection: UUIDv7?

    @ObservationIgnored public var onFocus: (@MainActor (UUIDv7) -> Void)?
    @ObservationIgnored public var onClose: (@MainActor (UUIDv7) -> Void)?
    @ObservationIgnored public var onCloseAll: (@MainActor () -> Void)?
    @ObservationIgnored public var onLayout: (@MainActor (TaskWindowLayout) -> Void)?
    @ObservationIgnored public var onOrder: (@MainActor (TaskWindowOrder) -> Void)?
    /// The new manual order after a drag.
    @ObservationIgnored public var onReorder: (@MainActor ([UUIDv7]) -> Void)?

    public init() {}

    public func move(from source: IndexSet, to destination: Int) {
        var ids = entries.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        onReorder?(ids)
    }
}

/// The Task Windows switcher (⌥⌘T): every open task window with its
/// priority and due date; sort, rearrange, click to bring one forward.
public struct TaskWindowsView: View {
    @Bindable var model: TaskWindowsModel

    public init(model: TaskWindowsModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.largeTitle)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    Text("No task windows are open")
                        .font(.headline)
                    Text("Open a task from the Today list and it appears here.")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.entries) { entry in
                        row(entry)
                            .tag(entry.id)
                    }
                    .onMove { source, destination in model.move(from: source, to: destination) }
                }
                .listStyle(.inset)
                .onKeyPress(.return) {
                    if let id = model.selection { model.onFocus?(id) }
                    return .handled
                }
                .onChange(of: model.selection) { _, id in
                    if let id { model.onFocus?(id) }
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, minHeight: 280, idealHeight: 420, maxHeight: .infinity)
        .background(DesignTokens.Palette.background)
        .tint(DesignTokens.Palette.accent)
        .accessibilityIdentifier("task-windows")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                controlTitle("Arrange")
                Picker("Arrange", selection: Binding(
                    get: { model.layout },
                    set: { model.onLayout?($0) }
                )) {
                    ForEach(TaskWindowLayout.allCases, id: \.self) { layout in
                        Text(layout == .sideBySide ? "Side" : layout.label)
                            .help(layout.label)
                            .tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 4) {
                controlTitle("Sort by")
                Picker("Sort by", selection: Binding(
                    get: { model.order },
                    set: { model.onOrder?($0) }
                )) {
                    ForEach(TaskWindowOrder.allCases, id: \.self) { order in
                        Text(order.shortLabel).help(order.label).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func controlTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.Palette.textSecondary)
    }

    private func row(_ entry: TaskWindowEntry) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: PriorityColor.hex(for: entry.priority, in: .dark)))
                .frame(width: 8, height: 8)
                .opacity(entry.isDone ? 0.3 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "Untitled task" : entry.title)
                    .font(.body.weight(entry.id == model.activeId ? .semibold : .regular))
                    .strikethrough(entry.isDone)
                    .lineLimit(1)
                Text(TaskWindowStack.dueLabel(entry))
                    .font(.caption)
                    .foregroundStyle(entry.dueAt < .now && !entry.isDone ? Color.red : DesignTokens.Palette.textSecondary)
            }
            Spacer(minLength: 4)
            if entry.id == model.activeId {
                Text("Front")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(DesignTokens.Palette.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(DesignTokens.Palette.accent)
            }
            Button {
                model.onClose?(entry.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignTokens.Palette.textSecondary)
            .help("Close this task window")
            .accessibilityLabel("Close \(entry.title)")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help("Click to bring this window forward. Drag to change the order.")
    }

    private var footer: some View {
        HStack {
            Text(model.entries.count == 1 ? "1 task window" : "\(model.entries.count) task windows")
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            Spacer()
            Button("Close All") { model.onCloseAll?() }
                .disabled(model.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
