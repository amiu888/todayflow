import SwiftUI
import Foundation
import TodayFlowCore
import TodayFlowDesign

/// A deliberately small visual workflow builder: each node is a tray, and
/// dragging from a tray's right handle to another tray creates one rule:
/// "when this happens in A, move the task to B."
@MainActor
@Observable
public final class WorkflowEditorModel {
    public struct TrayNode: Identifiable, Hashable {
        public let tray: WorkTray
        public var position: CGPoint
        public var id: UUIDv7 { tray.id }
    }

    public static let nodeSize = CGSize(width: 210, height: 78)

    public private(set) var nodes: [TrayNode] = []
    public private(set) var rules: [TrayWorkflowRule] = []
    public var selectedRuleID: UUIDv7?
    public private(set) var connectionSource: UUIDv7?
    public private(set) var connectionPoint: CGPoint?
    public private(set) var lastError: String?

    @ObservationIgnored private let today: TodayViewModel
    @ObservationIgnored private let repository: any SettingRepository

    public init(today: TodayViewModel, repository: any SettingRepository) {
        self.today = today
        self.repository = repository
    }

    public func load() async {
        if let raw = await repository.value(for: SettingKeys.workflowRules),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([TrayWorkflowRule].self, from: data)
        {
            rules = decoded
        } else {
            rules = []
        }
        rebuildNodes()
    }

    public func rebuildNodes() {
        let oldPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        let trays = today.trays.sorted { $0.sortOrder < $1.sortOrder }
        let columns = 2
        nodes = trays.enumerated().map { index, tray in
            let column = index % columns
            let row = index / columns
            let fallback = CGPoint(
                x: 140 + CGFloat(column) * 290,
                y: 80 + CGFloat(row) * 118
            )
            return TrayNode(
                tray: tray,
                position: oldPositions[tray.id] ?? fallback
            )
        }
        let trayIDs = Set(trays.map(\.id))
        rules = rules.filter {
            trayIDs.contains($0.sourceTrayId) && trayIDs.contains($0.targetTrayId)
        }
        if let selectedRuleID, !rules.contains(where: { $0.id == selectedRuleID }) {
            self.selectedRuleID = nil
        }
    }

    public var canvasSize: CGSize {
        let rows = max(1, (nodes.count + 1) / 2)
        return CGSize(width: 660, height: CGFloat(80 + rows * 118))
    }

    public func node(for trayId: UUIDv7) -> TrayNode? {
        nodes.first { $0.id == trayId }
    }

    public func trayName(_ id: UUIDv7) -> String {
        node(for: id)?.tray.name ?? "Missing tray"
    }

    public var selectedRule: TrayWorkflowRule? {
        guard let selectedRuleID else { return nil }
        return rules.first { $0.id == selectedRuleID }
    }

    public func sentence(_ rule: TrayWorkflowRule) -> String {
        let source = trayName(rule.sourceTrayId)
        let target = trayName(rule.targetTrayId)
        switch rule.trigger {
        case .completed:
            return "When a task in “\(source)” is completed, move it to “\(target)”."
        case .dueReached:
            return "When a task in “\(source)” reaches its due date, move it to “\(target)”."
        }
    }

    public func moveNode(_ id: UUIDv7, to point: CGPoint) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].position = clamp(point)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        let half = Self.nodeSize.width / 2
        return CGPoint(
            x: min(max(point.x, half + 8), canvasSize.width - half - 8),
            y: min(max(point.y, Self.nodeSize.height / 2 + 8), canvasSize.height - Self.nodeSize.height / 2 - 8)
        )
    }

    public func beginConnection(from id: UUIDv7, at point: CGPoint) {
        connectionSource = id
        connectionPoint = point
    }

    public func updateConnection(to point: CGPoint) {
        connectionPoint = point
    }

    public func finishConnection() async {
        guard let sourceId = connectionSource, let point = connectionPoint else {
            cancelConnection()
            return
        }
        cancelConnection()
        guard let target = nodes.first(where: {
            CGRect(
                x: $0.position.x - Self.nodeSize.width / 2,
                y: $0.position.y - Self.nodeSize.height / 2,
                width: Self.nodeSize.width,
                height: Self.nodeSize.height
            ).contains(point)
        }) else { return }
        guard target.id != sourceId else { return }
        await addRule(source: sourceId, target: target.id, trigger: .completed)
    }

    public func cancelConnection() {
        connectionSource = nil
        connectionPoint = nil
    }

    public func addRule(
        source: UUIDv7,
        target: UUIDv7,
        trigger: TrayWorkflowTrigger
    ) async {
        guard source != target else { return }
        if let existing = rules.first(where: {
            $0.sourceTrayId == source
                && $0.targetTrayId == target
                && $0.trigger == trigger
        }) {
            selectedRuleID = existing.id
            return
        }
        let rule = TrayWorkflowRule(
            sourceTrayId: source,
            targetTrayId: target,
            trigger: trigger
        )
        rules.append(rule)
        selectedRuleID = rule.id
        await save()
    }

    public func setTrigger(_ ruleID: UUIDv7, _ trigger: TrayWorkflowTrigger) async {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].trigger = trigger
        await save()
    }

    public func setEnabled(_ ruleID: UUIDv7, _ enabled: Bool) async {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].isEnabled = enabled
        await save()
    }

    public func deleteRule(_ ruleID: UUIDv7) async {
        rules.removeAll { $0.id == ruleID }
        if selectedRuleID == ruleID { selectedRuleID = nil }
        await save()
    }

    private func save() async {
        guard let data = try? JSONEncoder().encode(rules),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        do {
            try await repository.set(raw, for: SettingKeys.workflowRules)
            await today.runWorkflows()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

public struct WorkflowEditorView: View {
    @State private var model: WorkflowEditorModel

    public init(today: TodayViewModel, repository: any SettingRepository) {
        _model = State(initialValue: WorkflowEditorModel(today: today, repository: repository))
    }

    public init(model: WorkflowEditorModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.nodes.isEmpty {
                ContentUnavailableView(
                    "No trays yet",
                    systemImage: "tray",
                    description: Text("Create a working tray in Today, then come back to build a workflow.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    canvas
                    Divider()
                    inspector
                        .frame(width: 270)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .background(DesignTokens.Palette.background)
        .task { await model.load() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tray workflows")
                    .font(.title3.weight(.semibold))
                Text("Drag from a tray’s right handle to another tray. Every workflow is one trigger and one move; while it is on, it runs automatically.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Spacer()
            Label("Runs automatically while on", systemImage: "bolt.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
                .help("There is nothing to start. Turn a workflow on and it reacts to completions and due dates.")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var canvas: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                dotGrid
                wires
                ForEach(model.rules) { rule in
                    ruleLabel(rule)
                }
                ForEach(model.nodes) { node in
                    nodeView(node)
                }
            }
            .frame(width: model.canvasSize.width, height: model.canvasSize.height)
            .coordinateSpace(name: "workflowCanvas")
        }
    }

    private var dotGrid: some View {
        Canvas { context, size in
            let step: CGFloat = 22
            for x in stride(from: step, to: size.width, by: step) {
                for y in stride(from: step, to: size.height, by: step) {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(DesignTokens.Palette.hairline.opacity(0.55))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var wires: some View {
        Canvas { context, _ in
            for rule in model.rules {
                guard let source = model.node(for: rule.sourceTrayId),
                      let target = model.node(for: rule.targetTrayId)
                else { continue }
                let start = CGPoint(
                    x: source.position.x + WorkflowEditorModel.nodeSize.width / 2,
                    y: source.position.y
                )
                let end = CGPoint(
                    x: target.position.x - WorkflowEditorModel.nodeSize.width / 2,
                    y: target.position.y
                )
                let selected = rule.id == model.selectedRuleID
                drawWire(
                    from: start,
                    to: end,
                    color: selected
                        ? DesignTokens.Palette.accent
                        : DesignTokens.Palette.textSecondary.opacity(rule.isEnabled ? 0.55 : 0.28),
                    lineWidth: selected ? 2.5 : 1.5,
                    dashed: !rule.isEnabled,
                    in: &context
                )
            }
            if let sourceId = model.connectionSource,
               let start = model.node(for: sourceId),
               let point = model.connectionPoint
            {
                drawWire(
                    from: CGPoint(
                        x: start.position.x + WorkflowEditorModel.nodeSize.width / 2,
                        y: start.position.y
                    ),
                    to: point,
                    color: DesignTokens.Palette.accent,
                    lineWidth: 2,
                    dashed: true,
                    in: &context
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawWire(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        dashed: Bool = false,
        in context: inout GraphicsContext
    ) {
        let control = max(36, abs(end.x - start.x) * 0.45)
        var path = Path()
        path.move(to: start)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + control, y: start.y),
            control2: CGPoint(x: end.x - control, y: end.y)
        )
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                dash: dashed ? [6, 5] : []
            )
        )
        let angle = atan2(end.y - start.y, end.x - start.x)
        let size: CGFloat = 7
        var arrow = Path()
        arrow.move(to: end)
        arrow.addLine(to: CGPoint(
            x: end.x - size * cos(angle - .pi / 6),
            y: end.y - size * sin(angle - .pi / 6)
        ))
        arrow.addLine(to: CGPoint(
            x: end.x - size * cos(angle + .pi / 6),
            y: end.y - size * sin(angle + .pi / 6)
        ))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(color))
    }

    private func ruleLabel(_ rule: TrayWorkflowRule) -> some View {
        let source = model.node(for: rule.sourceTrayId)
        let target = model.node(for: rule.targetTrayId)
        let point = CGPoint(
            x: ((source?.position.x ?? 0) + (target?.position.x ?? 0)) / 2,
            y: ((source?.position.y ?? 0) + (target?.position.y ?? 0)) / 2
        )
        return HStack(spacing: 4) {
            Button {
                model.selectedRuleID = rule.id
            } label: {
                Text(rule.isEnabled ? rule.trigger.shortLabel : "\(rule.trigger.shortLabel) · off")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(
                        rule.isEnabled
                            ? (rule.id == model.selectedRuleID
                                ? DesignTokens.Palette.accent
                                : DesignTokens.Palette.textSecondary)
                            : DesignTokens.Palette.textSecondary.opacity(0.7)
                    )
            }
            .buttonStyle(.plain)

            Button {
                Task { await model.deleteRule(rule.id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove this workflow")
            .accessibilityLabel("Remove workflow \(model.trayName(rule.sourceTrayId)) to \(model.trayName(rule.targetTrayId))")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(DesignTokens.Palette.surface))
        .overlay(
            Capsule().stroke(
                rule.id == model.selectedRuleID
                    ? DesignTokens.Palette.accent.opacity(0.6)
                    : DesignTokens.Palette.hairline,
                lineWidth: 1
            )
        )
        .contextMenu {
            Button("Remove workflow", role: .destructive) {
                Task { await model.deleteRule(rule.id) }
            }
        }
        .position(point)
    }

    private func nodeView(_ node: WorkflowEditorModel.TrayNode) -> some View {
        let tint = Color(
            hex: node.tray.colorHex
                ?? DesignTokens.TrayPalette.colorHex(at: node.tray.sortOrder)
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: DesignTokens.TrayPalette.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(node.tray.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(node.tray.itemIds.count)")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            Text("Drag the right handle to connect")
                .font(.system(size: 9))
                .foregroundStyle(DesignTokens.Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(width: WorkflowEditorModel.nodeSize.width, height: WorkflowEditorModel.nodeSize.height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(tint.opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Circle()
                .fill(DesignTokens.Palette.surfaceRaised)
                .overlay(Circle().stroke(DesignTokens.Palette.hairline, lineWidth: 1))
                .frame(width: 10, height: 10)
                .offset(x: -5)
        }
        .overlay(alignment: .trailing) {
            Circle()
                .fill(tint)
                .frame(width: 13, height: 13)
                .overlay(Circle().stroke(DesignTokens.Palette.background, lineWidth: 2))
                .offset(x: 6)
                .contentShape(Circle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("workflowCanvas"))
                        .onChanged { value in
                            if model.connectionSource == nil {
                                model.beginConnection(from: node.id, at: value.location)
                            } else {
                                model.updateConnection(to: value.location)
                            }
                        }
                        .onEnded { _ in
                            Task { await model.finishConnection() }
                        }
                )
                .help("Drag to another tray to create a workflow")
        }
        .position(node.position)
        .gesture(
            DragGesture(coordinateSpace: .named("workflowCanvas"))
                .onChanged { value in
                    model.moveNode(node.id, to: value.location)
                }
        )
        .onTapGesture {
            model.selectedRuleID = model.rules.first(where: {
                $0.sourceTrayId == node.id || $0.targetTrayId == node.id
            })?.id
        }
        .accessibilityLabel("Tray \(node.tray.name)")
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Rules")
                    .font(.callout.weight(.semibold))

                if let rule = model.selectedRule {
                    Text(model.sentence(rule))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("When", selection: Binding(
                        get: { rule.trigger },
                        set: { trigger in
                            Task { await model.setTrigger(rule.id, trigger) }
                        }
                    )) {
                        ForEach(TrayWorkflowTrigger.allCases) { trigger in
                            Text(trigger.label).tag(trigger)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Toggle("Workflow is on", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { enabled in
                            Task { await model.setEnabled(rule.id, enabled) }
                        }
                    ))
                    Text(rule.isEnabled
                        ? "Runs automatically when its trigger happens."
                        : "Paused. It won’t move tasks until you turn it back on.")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)

                    Button("Delete rule", role: .destructive) {
                        Task { await model.deleteRule(rule.id) }
                    }
                    .buttonStyle(.borderless)

                    Divider()
                } else {
                    Text("Drag from a tray’s right handle onto another tray, then choose when the move should happen.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.rules.isEmpty {
                    Text("No rules yet.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                } else {
                    ForEach(model.rules) { rule in
                        Button {
                            model.selectedRuleID = rule.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(model.trayName(rule.sourceTrayId)) → \(model.trayName(rule.targetTrayId))")
                                    .font(.caption.weight(.semibold))
                                HStack(spacing: 5) {
                                    Text(rule.trigger.label)
                                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                                    Text(rule.isEnabled ? "On" : "Off")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(
                                            rule.isEnabled
                                                ? DesignTokens.Palette.accent
                                                : DesignTokens.Palette.textSecondary.opacity(0.7)
                                        )
                                }
                                .font(.caption2)
                            }
                            .opacity(rule.isEnabled ? 1 : 0.65)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(7)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(
                                        rule.id == model.selectedRuleID
                                            ? DesignTokens.Palette.accent.opacity(0.14)
                                            : DesignTokens.Palette.surface
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.danger)
                }
            }
            .padding(14)
        }
    }
}
