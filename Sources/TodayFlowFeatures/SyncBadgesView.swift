import SwiftUI
import TodayFlowDesign

/// One sync connection's state, as a badge shows it.
public enum SyncBadgeState: Equatable, Sendable {
    /// Paired or set up, but switched off.
    case off
    case syncing
    case synced
    /// Local changes not sent yet.
    case waiting(Int)
    case failed(String)
}

public struct SyncBadgeStatus: Equatable, Sendable {
    public var state: SyncBadgeState
    public var lastSyncAt: Date?

    public init(state: SyncBadgeState, lastSyncAt: Date? = nil) {
        self.state = state
        self.lastSyncAt = lastSyncAt
    }
}

/// The two badges in the Today header. `nil` hides a badge (not set up).
@MainActor
@Observable
public final class SyncBadgesModel {
    public var server: SyncBadgeStatus?
    public var obsidian: SyncBadgeStatus?
    @ObservationIgnored public var onOpenServer: (@MainActor () -> Void)?
    @ObservationIgnored public var onOpenObsidian: (@MainActor () -> Void)?

    public init() {}

    public var isEmpty: Bool { server == nil && obsidian == nil }
}

/// "● Server  ● Obsidian": green synced, blue syncing, orange waiting,
/// red failed, grey off. Hover for details; click to open its settings.
struct SyncBadgesView: View {
    let model: SyncBadgesModel

    var body: some View {
        HStack(spacing: 4) {
            if let server = model.server {
                SyncBadge(name: "Server", status: server, action: model.onOpenServer)
                    .accessibilityIdentifier("sync-badge-server")
            }
            if let obsidian = model.obsidian {
                SyncBadge(name: "Obsidian", status: obsidian, action: model.onOpenObsidian)
                    .accessibilityIdentifier("sync-badge-obsidian")
            }
        }
        .fixedSize()
    }
}

struct SyncBadge: View {
    let name: String
    let status: SyncBadgeStatus
    let action: (@MainActor () -> Void)?
    @State private var pulse = false

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(status.state == .syncing && pulse ? 0.35 : 1)
                Text(name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Self.helpText(name: name, status: status))
        .accessibilityLabel("\(name) sync: \(Self.stateText(status.state))")
        .onAppear { startPulse() }
        .onChange(of: status.state) { _, _ in startPulse() }
    }

    private func startPulse() {
        guard status.state == .syncing else { pulse = false; return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
    }

    private var color: Color {
        switch status.state {
        case .synced: return Color(hex: "#0ca30c")
        case .syncing: return DesignTokens.Palette.accent
        case .waiting: return .orange
        case .failed: return .red
        case .off: return .gray
        }
    }

    static func stateText(_ state: SyncBadgeState) -> String {
        switch state {
        case .synced: return "up to date"
        case .syncing: return "syncing"
        case .waiting(let count): return count == 1 ? "1 change waiting" : "\(count) changes waiting"
        case .failed: return "not syncing"
        case .off: return "off"
        }
    }

    static func helpText(name: String, status: SyncBadgeStatus) -> String {
        var text: String
        switch status.state {
        case .failed(let message): text = "\(name): \(message)"
        default: text = "\(name): \(stateText(status.state))"
        }
        if let last = status.lastSyncAt {
            text += "\nLast synced \(last.formatted(.relative(presentation: .named)))"
        }
        return text + "\nClick for \(name) settings."
    }
}
