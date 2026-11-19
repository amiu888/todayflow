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
    /// Extra lines for the popover ("Server: …", "This Mac: …").
    public var details: [String]
    /// Recent rounds, newest first (server only).
    public var log: [SyncLogEntry]

    public init(state: SyncBadgeState, lastSyncAt: Date? = nil, details: [String] = [], log: [SyncLogEntry] = []) {
        self.state = state
        self.lastSyncAt = lastSyncAt
        self.details = details
        self.log = log
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
    @ObservationIgnored public var onSyncServerNow: (@MainActor () -> Void)?
    @ObservationIgnored public var onSyncObsidianNow: (@MainActor () -> Void)?

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
                SyncBadge(
                    target: .server, status: server,
                    onSyncNow: model.onSyncServerNow, onOpenSettings: model.onOpenServer
                )
                .accessibilityIdentifier("sync-badge-server")
            }
            if let obsidian = model.obsidian {
                SyncBadge(
                    target: .obsidian, status: obsidian,
                    onSyncNow: model.onSyncObsidianNow, onOpenSettings: model.onOpenObsidian
                )
                .accessibilityIdentifier("sync-badge-obsidian")
            }
        }
        .fixedSize()
    }
}

struct SyncBadge: View {
    enum Target { case server, obsidian }

    let target: Target
    let status: SyncBadgeStatus
    let onSyncNow: (@MainActor () -> Void)?
    let onOpenSettings: (@MainActor () -> Void)?
    @State private var pulse = false
    @State private var showingDetails = false

    var name: String { target == .server ? "Server" : "Obsidian" }

    var body: some View {
        Button {
            showingDetails.toggle()
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
        .help(Self.helpText(target: target, status: status))
        .accessibilityLabel("\(name) sync: \(Self.stateText(status.state))")
        .popover(isPresented: $showingDetails, arrowEdge: .bottom) { details }
        .onAppear { startPulse() }
        .onChange(of: status.state) { _, _ in startPulse() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text("\(name): \(Self.stateText(status.state))").font(.headline)
            }
            Text(Self.meaning(target: target, state: status.state))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            if let last = status.lastSyncAt {
                Text("Last synced \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(status.details, id: \.self) { line in
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
            if !status.log.isEmpty {
                Divider()
                Text("Recent activity").font(.caption.weight(.semibold))
                ForEach(status.log.prefix(6)) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.time, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(entry.details.first.map { entry.summary + " · " + $0 } ?? entry.summary)
                            .font(.caption)
                            .foregroundStyle(entry.isError ? .red : .primary)
                            .lineLimit(2)
                    }
                }
            }
            Divider()
            HStack {
                if let onOpenSettings {
                    Button("\(name) Settings…") {
                        showingDetails = false
                        onOpenSettings()
                    }
                }
                Spacer()
                if let onSyncNow, status.state != .off {
                    Button("Sync Now") { onSyncNow() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
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

    /// What the color means, in plain words.
    static func meaning(target: Target, state: SyncBadgeState) -> String {
        switch (target, state) {
        case (.server, .synced):
            return "Green: everything on this Mac is on the server, and the latest changes from your other Macs are here. TodayFlow checks every 10 seconds."
        case (.server, .syncing):
            return "Blue: sending this Mac's changes to the server right now."
        case (.server, .waiting(let count)):
            return "Orange: \(count == 1 ? "1 change" : "\(count) changes") on this Mac \(count == 1 ? "hasn't" : "haven't") reached the server yet. \(count == 1 ? "It goes" : "They go") in the next round, within 10 seconds."
        case (.server, .failed(let message)):
            return "Red: not syncing. \(message) Your changes are kept on this Mac and sent once it works again."
        case (.server, .off):
            return "Grey: this Mac is paired but sync is switched off. Nothing is sent or received."
        case (.obsidian, .synced):
            return "Green: the TodayFlow note in Obsidian matches your tasks, and edits made in the note have been read back. TodayFlow checks every 3 seconds."
        case (.obsidian, .failed(let message)):
            return "Red: can't update the Obsidian note. \(message)"
        case (.obsidian, .syncing):
            return "Blue: updating the Obsidian note."
        case (.obsidian, .waiting):
            return "Orange: the Obsidian note is about to be updated."
        case (.obsidian, .off):
            return "Grey: Obsidian sync is switched off."
        }
    }

    static func helpText(target: Target, status: SyncBadgeStatus) -> String {
        var text = meaning(target: target, state: status.state)
        if let last = status.lastSyncAt {
            text += "\nLast synced \(last.formatted(.relative(presentation: .named)))."
        }
        return text + "\nClick for details."
    }
}
