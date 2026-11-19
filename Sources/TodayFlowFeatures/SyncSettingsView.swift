import SwiftUI
import TodayFlowCore

/// One entry of the sync log: a round that moved something, or an error.
public struct SyncLogEntry: Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var time: Date
    /// "Sent 2, received 1" or the error.
    public var summary: String
    /// "Sent task “Plan trip”", "Downloaded Pasted image.png"…
    public var details: [String]
    public var isError: Bool

    public init(time: Date, summary: String, details: [String] = [], isError: Bool = false) {
        self.time = time
        self.summary = summary
        self.details = details
        self.isError = isError
    }
}

/// What the Sync tab shows.
public struct SyncSnapshot: Equatable, Sendable {
    public var isPaired = false
    public var serverAddress = ""
    /// The server user this Mac syncs as.
    public var userName: String?
    public var deviceName = ""
    public var isEnabled = false
    public var isSyncing = false
    public var lastSyncAt: Date?
    public var pendingCount = 0
    public var lastError: String?
    /// "Received 3, sent 2" from the last round.
    public var lastResult: String?
    /// Attachment files this Mac can't upload, as "name: reason".
    public var skippedFiles: [String] = []
    /// Newest first; rounds that moved nothing are not listed.
    public var log: [SyncLogEntry] = []
    /// When the server was last checked, even if nothing moved.
    public var lastCheckedAt: Date?

    public init() {}
}

/// The app side of the Sync tab; `SyncController` in the Mac target.
@MainActor
public protocol SyncPanelBackend: AnyObject, Observable {
    var snapshot: SyncSnapshot { get }
    /// Pairs this Mac. Returns an error message, or nil on success.
    func pair(server: String, code: String) async -> String?
    func unpair() async
    func setEnabled(_ enabled: Bool) async
    func syncNow() async
    func refresh() async
}

/// Settings ▸ Sync: connect this Mac to a TodayFlow server.
struct SyncSettingsSection: View {
    let backend: any SyncPanelBackend
    @State private var server = ""
    @State private var code = ""
    @State private var pairError: String?
    @State private var isPairing = false
    @State private var confirmUnpair = false

    var body: some View {
        let state = backend.snapshot
        Group {
            if state.isPaired {
                pairedSections(state)
            } else {
                pairSection
            }
        }
        .task {
            await backend.refresh()
            if server.isEmpty { server = state.serverAddress }
        }
    }

    private var pairSection: some View {
        Section {
            TextField("Server address", text: $server, prompt: Text(verbatim: "http://nas.local:8787"))
                .textContentType(.URL)
                .autocorrectionDisabled()
            TextField("Pairing code", text: $code, prompt: Text("From the server's admin page"))
                .autocorrectionDisabled()

            if let pairError {
                Label(pairError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if isPairing { ProgressView().controlSize(.small) }
                Button("Pair") { Task { await pair() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isPairing || server.isEmpty || code.isEmpty)
            }
        } header: {
            Text("Connect to a server")
        } footer: {
            Text("Get a pairing code from the server's admin page (Users ▸ Add user). Pairing makes a backup of this Mac's data first; sync stays off until you turn it on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func pairedSections(_ state: SyncSnapshot) -> some View {
        Section("Server") {
            LabeledContent("Address", value: state.serverAddress)
            LabeledContent("User") {
                if let name = state.userName {
                    Text(name)
                } else {
                    Text("Checking…").foregroundStyle(.secondary)
                }
            }
            .help("The server user this Mac syncs as. Every Mac paired with this user's code shares the same tasks.")
            LabeledContent("This Mac", value: state.deviceName)
            Toggle("Sync", isOn: Binding(
                get: { state.isEnabled },
                set: { on in Task { await backend.setEnabled(on) } }
            ))
        }

        Section("Status") {
            LabeledContent("Last synced") {
                if state.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Syncing…")
                    }
                } else if let last = state.lastSyncAt {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Changes waiting to send", value: "\(state.pendingCount)")
            if let result = state.lastResult {
                LabeledContent("Last round", value: result)
            }
            if !state.skippedFiles.isEmpty {
                DisclosureGroup("\(state.skippedFiles.count) file(s) not synced") {
                    ForEach(state.skippedFiles, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Changes waiting to send counts edits on this Mac that haven't gone to the server yet. It goes up for a moment after an edit and back to 0 within 10 seconds, once the change is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Unpair This Mac…", role: .destructive) { confirmUnpair = true }
                Spacer()
                Button("Sync Now") { Task { await backend.syncNow() } }
                    .disabled(!state.isEnabled || state.isSyncing)
            }
        }

        Section {
            if state.log.isEmpty {
                Text("Nothing synced yet. Each round that sends or receives something is listed here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.log.prefix(30)) { entry in
                    SyncLogRow(entry: entry)
                }
            }
        } header: {
            Text("Activity")
        } footer: {
            Text("Also written to ~/Library/Logs/TodayFlow/app.log. The server is checked every 10 seconds; rounds where nothing changed aren't listed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Unpair this Mac from the server?",
            isPresented: $confirmUnpair
        ) {
            Button("Unpair", role: .destructive) { Task { await backend.unpair() } }
        } message: {
            Text("Your tasks stay on this Mac, and nothing is deleted on the server. To sync again, pair with a new code.")
        }
    }

    private func pair() async {
        isPairing = true
        pairError = nil
        defer { isPairing = false }
        if let error = await backend.pair(server: server, code: code) {
            pairError = error
        } else {
            code = ""
        }
    }
}

/// One sync round in the Activity list; click to see what moved.
struct SyncLogRow: View {
    let entry: SyncLogEntry
    @State private var expanded = false

    var body: some View {
        if entry.details.isEmpty {
            label
        } else {
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(Array(entry.details.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            Text(entry.time, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if entry.isError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
            }
            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(entry.isError ? .red : .primary)
                .lineLimit(2)
        }
    }
}
