#if os(iOS)
import SwiftUI
import TodayFlowCore
import TodayFlowFeatures

/// Settings (docs/ios/DESIGN.md §3.6): sync, notifications, work hours, about.
struct PhoneSettingsView: View {
    let environment: PhoneEnvironment
    let sync: SyncController?
    @Bindable var notifications: PhoneNotificationSettings
    @Environment(\.dismiss) private var dismiss

    @State private var hours = WorkCalendarSettings()

    var body: some View {
        Form {
            if let sync {
                PhoneSyncSection(sync: sync)
            }

            Section {
                Toggle("Task reminders", isOn: $notifications.remindersOn)
                Toggle("Due-soon nudges", isOn: $notifications.nudgesOn)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Nudges arrive 12 hours, 5 hours and 1 hour before a task is due.")
            }

            Section("Work hours") {
                Stepper("Start \(Self.hourText(hours.startHour))", value: $hours.startHour, in: 0...(hours.endHour - 1))
                Stepper("End \(Self.hourText(hours.endHour))", value: $hours.endHour, in: (hours.startHour + 1)...24)
                weekdays
            }
            .onChange(of: hours) { Task { await saveHours() } }

            Section("About") {
                LabeledContent("Version", value: Self.version)
                Link("TodayFlow tutorials", destination: URL(string: "https://github.com/amiu888/todayflow/tree/main/docs/tutorials")!)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task {
            if let raw = await environment.settings.value(for: SettingKeys.workCalendar),
               let stored = try? JSONDecoder().decode(WorkCalendarSettings.self, from: Data(raw.utf8)) {
                hours = stored
            }
        }
    }

    private var weekdays: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return HStack {
            ForEach(1...7, id: \.self) { day in
                let on = hours.workWeekdays.contains(day)
                Button(symbols[day - 1]) {
                    if on {
                        hours.workWeekdays.removeAll { $0 == day }
                    } else {
                        hours.workWeekdays = (hours.workWeekdays + [day]).sorted()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(on ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1), in: .circle)
                .foregroundStyle(on ? Color.accentColor : .secondary)
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
            }
        }
    }

    private func saveHours() async {
        guard let data = try? JSONEncoder().encode(hours), let json = String(data: data, encoding: .utf8) else { return }
        try? await environment.settings.set(json, for: SettingKeys.workCalendar)
        await environment.loadSettings()
    }

    static func hourText(_ hour: Double) -> String {
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(hour * 3600)
        return date.formatted(date: .omitted, time: .shortened)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Settings ▸ Sync on the phone: the same pairing as the Mac (server address
/// plus a pairing code from the server's admin page).
struct PhoneSyncSection: View {
    let sync: SyncController
    @State private var server = ""
    @State private var code = ""
    @State private var pairError: String?
    @State private var isPairing = false
    @State private var confirmUnpair = false

    var body: some View {
        let state = sync.snapshot
        Group {
            if state.isPaired {
                paired(state)
            } else {
                pairSection
            }
        }
        .task {
            await sync.refresh()
            if server.isEmpty { server = state.serverAddress }
            // Builds made for one person's own server pre-fill its address.
            if server.isEmpty,
               let fallback = Bundle.main.object(forInfoDictionaryKey: "TodayFlowDefaultServer") as? String,
               !fallback.isEmpty {
                server = fallback
            }
        }
    }

    private var pairSection: some View {
        Section {
            TextField("Server address", text: $server, prompt: Text(verbatim: "http://nas.local:8787"))
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Pairing code", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            if let pairError {
                Label(pairError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button {
                Task { await pair() }
            } label: {
                HStack {
                    Text("Pair")
                    if isPairing { Spacer(); ProgressView() }
                }
            }
            .disabled(isPairing || server.isEmpty || code.isEmpty)
        } header: {
            Text("Sync")
        } footer: {
            Text("Get a pairing code from the server's admin page (Users ▸ Add user), using the same user as your Mac. Away from home, use the server's Tailscale address.")
        }
    }

    @ViewBuilder
    private func paired(_ state: SyncSnapshot) -> some View {
        Section("Sync") {
            Toggle("Sync", isOn: Binding(
                get: { state.isEnabled },
                set: { on in Task { await sync.setEnabled(on) } }
            ))
            LabeledContent("Server", value: state.serverAddress)
            if let user = state.userName { LabeledContent("User", value: user) }
            LabeledContent("This iPhone", value: state.deviceName)
            LabeledContent("Last synced") {
                if state.isSyncing {
                    ProgressView()
                } else if let last = state.lastSyncAt {
                    Text(last, format: .relative(presentation: .named))
                } else {
                    Text("Never").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Waiting to send", value: "\(state.pendingCount)")
            if let error = state.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Button("Sync Now") { Task { await sync.syncNow() } }
                .disabled(!state.isEnabled || state.isSyncing)
            Button("Unpair This iPhone…", role: .destructive) { confirmUnpair = true }
        }
        .confirmationDialog("Unpair this iPhone from the server?", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) { Task { await sync.unpair() } }
        } message: {
            Text("Your tasks stay on this iPhone, and nothing is deleted on the server.")
        }
        if !state.log.isEmpty {
            Section("Sync activity") {
                ForEach(state.log.prefix(20)) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.summary)
                            .font(.callout)
                            .foregroundStyle(entry.isError ? .red : .primary)
                        Text(entry.time.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func pair() async {
        isPairing = true
        pairError = nil
        defer { isPairing = false }
        if let error = await sync.pair(server: server, code: code) {
            pairError = error
        } else {
            code = ""
        }
    }
}
#endif
