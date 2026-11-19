import SwiftUI
import TodayFlowCore

/// What the Sync tab shows.
public struct SyncSnapshot: Equatable, Sendable {
    public var isPaired = false
    public var serverAddress = ""
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
            HStack {
                Button("Unpair This Mac…", role: .destructive) { confirmUnpair = true }
                Spacer()
                Button("Sync Now") { Task { await backend.syncNow() } }
                    .disabled(!state.isEnabled || state.isSyncing)
            }
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
