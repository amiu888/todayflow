import SwiftUI
import TodayFlowCore
import TodayFlowDesign
#if canImport(AppKit)
import AppKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The settings window (driver.md §11 feature 5): business hours and the
/// AI endpoint (driver.md §8).
public struct SettingsView: View {
    public let model: SettingsViewModel
    private let onOpenAISetup: (@MainActor @Sendable () -> Void)?
    private let onWatchTutorial: (@MainActor @Sendable () -> Void)?
    private let onObsidianSyncNow: (@MainActor @Sendable () -> Void)?
    private let onObsidianOpenNote: (@MainActor @Sendable () -> Void)?

    public init(
        model: SettingsViewModel,
        onOpenAISetup: (@MainActor @Sendable () -> Void)? = nil,
        onWatchTutorial: (@MainActor @Sendable () -> Void)? = nil,
        onObsidianSyncNow: (@MainActor @Sendable () -> Void)? = nil,
        onObsidianOpenNote: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.model = model
        self.onOpenAISetup = onOpenAISetup
        self.onWatchTutorial = onWatchTutorial
        self.onObsidianSyncNow = onObsidianSyncNow
        self.onObsidianOpenNote = onObsidianOpenNote
    }

    /// For hosts that only know the repositories (used by the 6-Mac app layer).
    @MainActor
    public init(
        repository: any SettingRepository,
        keychain: any KeychainStore,
        calendar: Calendar = .current,
        modelCatalog: (any AIModelCatalog)? = nil,
        onOpenAISetup: (@MainActor @Sendable () -> Void)? = nil,
        onWatchTutorial: (@MainActor @Sendable () -> Void)? = nil,
        onObsidianSyncNow: (@MainActor @Sendable () -> Void)? = nil,
        onObsidianOpenNote: (@MainActor @Sendable () -> Void)? = nil
    ) {
        model = SettingsViewModel(
            repository: repository,
            keychain: keychain,
            calendar: calendar,
            modelCatalog: modelCatalog
        )
        self.onOpenAISetup = onOpenAISetup
        self.onWatchTutorial = onWatchTutorial
        self.onObsidianSyncNow = onObsidianSyncNow
        self.onObsidianOpenNote = onObsidianOpenNote
    }

    @MainActor
    public var body: some View {
        @Bindable var model = model
        return Form {
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Section("Business hours") {
                Picker("Start", selection: $model.calendarSettings.startHour) {
                    ForEach(0..<24) { hour in
                        Text(String(format: "%02d:00", hour)).tag(Double(hour))
                    }
                }
                Picker("End", selection: $model.calendarSettings.endHour) {
                    ForEach(0..<24) { hour in
                        Text(String(format: "%02d:00", hour)).tag(Double(hour))
                    }
                }
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(Self.weekdayName(weekday), isOn: weekdayBinding(weekday))
                }
            }

            Section("Obsidian") {
                Toggle("Sync with Obsidian", isOn: $model.obsidianSettings.enabled)

                Picker("Connection", selection: $model.obsidianSettings.mode) {
                    Text("This Mac").tag(ObsidianSettings.Mode.local)
                    Text("Remote (LAN)").tag(ObsidianSettings.Mode.remote)
                }
                .pickerStyle(.segmented)

                if model.obsidianSettings.mode == .local {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(model.obsidianVaults) { vault in
                                Button {
                                    applyObsidianVault(vault)
                                } label: {
                                    HStack {
                                        Text(vault.name)
                                        if vault.path == model.obsidianSettings.vaultPath {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }

                            if !model.obsidianVaults.isEmpty {
                                Divider()
                            }

                            Button("Choose Folder…") {
                                chooseObsidianVault()
                            }
                        } label: {
                            Label(
                                model.obsidianSettings.vaultPath.isEmpty
                                    ? "Choose Vault"
                                    : model.obsidianSettings.resolvedVaultName,
                                systemImage: "folder"
                            )
                        }
                        .fixedSize()

                        Spacer()

                        Text(
                            model.obsidianSettings.vaultPath.isEmpty
                                ? "No vault selected"
                                : model.obsidianSettings.vaultPath
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }

                    Text("Vaults detected from Obsidian appear here — for example NBCBrain or HermesBrain. Choose Folder… for any other vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Vault name", text: $model.obsidianSettings.vaultName)
                    Text("Vault name is used for obsidian:// links; it is usually the folder name.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            Task { @MainActor in await self.model.scanObsidianLAN() }
                        } label: {
                            Label("Find Obsidian on LAN", systemImage: "wifi")
                        }
                        .disabled(model.isScanningObsidian)

                        if model.isScanningObsidian {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if !model.obsidianDiscoveredServers.isEmpty {
                        Picker("Discovered", selection: Binding(
                            get: {
                                model.obsidianDiscoveredServers.first {
                                    $0.host == model.obsidianSettings.remoteHost
                                        && $0.port == model.obsidianSettings.remotePort
                                        && $0.useHTTPS == model.obsidianSettings.remoteUseHTTPS
                                }?.id ?? ""
                            },
                            set: { id in
                                if let server = model.obsidianDiscoveredServers.first(where: { $0.id == id }) {
                                    model.applyObsidianServer(server)
                                }
                            }
                        )) {
                            Text("Choose a server…").tag("")
                            ForEach(model.obsidianDiscoveredServers) { server in
                                Text(server.displayName).tag(server.id)
                            }
                        }
                    }

                    LabeledContent("Host") {
                        TextField("192.168.1.50", text: $model.obsidianSettings.remoteHost)
                    }
                    LabeledContent("Port") {
                        TextField(
                            "Port",
                            value: $model.obsidianSettings.remotePort,
                            format: .number
                        )
                        .frame(width: 80)
                    }

                    Toggle("Use HTTPS (self-signed certificate)", isOn: $model.obsidianSettings.remoteUseHTTPS)

                    SecureField("API key", text: $model.obsidianAPIKey)
                    HStack(spacing: 10) {
                        Button("Test connection") {
                            Task { @MainActor in await self.model.testObsidianConnection() }
                        }
                        if let status = model.obsidianConnectionStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("On the remote Obsidian: install Local REST API, set its binding host to 0.0.0.0, enable the HTTP server (27123) or HTTPS (27124), and copy the API key. TodayFlow accepts the plugin's self-signed HTTPS certificate for this connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link("Install Local REST API", destination: TutorialLinks.obsidianPlugin)
                }

                HStack(spacing: 8) {
                    TextField("Note path", text: $model.obsidianSettings.notePath)
                    if model.obsidianSettings.mode == .local {
                        Button("Folder…") {
                            chooseObsidianNoteFolder()
                        }
                        .help("Choose a folder inside the vault for the sync note")
                    }
                }
                Text("The note path is relative to the vault. For remote mode it is relative to the vault open in the remote Obsidian.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Sync now") {
                        Task { @MainActor in
                            await model.save()
                            onObsidianSyncNow?()
                        }
                    }
                    .disabled(model.isSaving)

                    Button("Open sync note") {
                        Task { @MainActor in
                            await model.save()
                            onObsidianOpenNote?()
                        }
                    }
                    .disabled(model.isSaving)
                }

                Text("Two-way sync for checkbox status, titles, tags, and due dates. New checklist lines become tasks. Everything outside TodayFlow's markers is left untouched. Disable this at any time; the rest of the app never depends on Obsidian.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link("Obsidian guide", destination: TutorialLinks.obsidian)
            }

            Section("AI") {
                Toggle("Enable AI", isOn: $model.aiSettings.enabled)
                if model.aiSettings.enabled {
                    Picker("Provider", selection: $model.aiSettings.provider) {
                        ForEach(AIEndpointSettings.Provider.allCases, id: \.self) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    if model.aiSettings.provider == .apple {
                        if appleIntelligenceAvailable {
                            Label(
                                "Apple Intelligence is available on this Mac. No API key or network request.",
                                systemImage: "checkmark.seal"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } else {
                            Label(
                                "Apple Intelligence is not available here. Choose Ollama, LM Studio, OpenAI, or a custom OpenAI-compatible endpoint.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        TextField("Base URL", text: $model.aiSettings.baseURL)
                        TextField("API key", text: $model.aiSettings.apiKey)

                        HStack {
                            TextField("Model", text: $model.aiSettings.model)

                            if model.modelCatalogAvailable {
                                Button(model.isFetchingModels ? "Fetching…" : "Fetch models") {
                                    Task { @MainActor in await model.fetchModels() }
                                }
                                .disabled(model.isFetchingModels)
                            }
                        }

                        if !model.availableModels.isEmpty {
                            Picker("Available models", selection: $model.aiSettings.model) {
                                ForEach(model.availableModels, id: \.self) { identifier in
                                    Text(identifier).tag(identifier)
                                }
                            }
                        }

                        Toggle("Send attachment text", isOn: $model.aiSettings.sendAttachmentText)
                        Stepper(
                            "Timeout \(Int(model.aiSettings.timeoutSeconds)) s",
                            value: $model.aiSettings.timeoutSeconds,
                            in: 5.0...120.0,
                            step: 5.0
                        )
                    }
                    if model.aiSettings.provider == .apple {
                        Toggle(
                            AIFeatures.label(for: AIFeatures.summarizeEmail),
                            isOn: featureBinding(AIFeatures.summarizeEmail)
                        )
                        Text("Apple Intelligence currently powers on-device email summaries.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(AIFeatures.all, id: \.self) { feature in
                            Toggle(AIFeatures.label(for: feature), isOn: featureBinding(feature))
                        }
                    }
                } else {
                    Text("AI is off by default. Enable it to use the AI features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let onOpenAISetup {
                    Divider()
                    Button {
                        onOpenAISetup()
                    } label: {
                        Label("AI setup & local models…", systemImage: "sparkles")
                    }
                    Text("Scans GPU Buddy/llama.cpp, Ollama, LM Studio, vLLM, text-generation-webui, and Jan on localhost. Also offers a 533 MB Qwen3.5 0.8B download; nothing is downloaded until you choose.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Help") {
                if let onWatchTutorial {
                    Button {
                        onWatchTutorial()
                    } label: {
                        Label("Watch the video walkthrough", systemImage: "play.rectangle")
                    }
                } else {
                    Link(destination: TutorialLinks.video) {
                        Label("Watch the video walkthrough", systemImage: "play.rectangle")
                    }
                }
                Link(destination: TutorialLinks.index) {
                    Label("Tutorials & guides on GitHub", systemImage: "book")
                }
            }

            Section {
                HStack {
                    Button("Reset to defaults") {
                        Task { @MainActor in await model.resetToDefaults() }
                    }
                    .disabled(model.isLoading || model.isSaving)

                    Spacer()

                    Button("Save") {
                        Task { @MainActor in await model.save() }
                    }
                    .disabled(model.isLoading || model.isSaving)
                }
            }
        }
        .frame(width: DesignTokens.Window.settings.width, height: DesignTokens.Window.settings.height)
        .task { await model.load() }
    }

    // MARK: Bindings (manual — the stored `model` is a plain `let`)

    private func weekdayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { model.calendarSettings.workWeekdays.contains(weekday) },
            set: { isOn in
                if isOn {
                    if !model.calendarSettings.workWeekdays.contains(weekday) {
                        model.calendarSettings.workWeekdays.append(weekday)
                        model.calendarSettings.workWeekdays.sort()
                    }
                } else {
                    model.calendarSettings.workWeekdays.removeAll { $0 == weekday }
                }
            }
        )
    }

    private func featureBinding(_ feature: String) -> Binding<Bool> {
        Binding(
            get: { model.aiSettings.enabledFeatures.contains(feature) },
            set: { isOn in
                if isOn {
                    if !model.aiSettings.enabledFeatures.contains(feature) {
                        model.aiSettings.enabledFeatures.append(feature)
                    }
                } else {
                    model.aiSettings.enabledFeatures.removeAll { $0 == feature }
                }
            }
        )
    }

    private var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }

    private func applyObsidianVault(_ vault: ObsidianVault) {
        model.obsidianSettings.vaultPath = vault.path
        model.obsidianSettings.vaultName = vault.name
        if model.obsidianSettings.notePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.obsidianSettings.notePath = ObsidianSettings.defaultNotePath
        }
        model.obsidianSettings.enabled = true
    }

    private func chooseObsidianNoteFolder() {
        #if canImport(AppKit)
        let vaultPath = model.obsidianSettings.vaultPath
        guard !vaultPath.isEmpty else { return }
        let vaultURL = URL(fileURLWithPath: vaultPath, isDirectory: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = vaultURL
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder inside the vault for the TodayFlow sync note."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let vault = vaultURL.standardizedFileURL.path
        let selected = url.standardizedFileURL.path
        var relative = ""
        if selected.hasPrefix(vault + "/") {
            relative = String(selected.dropFirst(vault.count + 1))
        }
        while relative.hasPrefix("/") { relative.removeFirst() }
        model.obsidianSettings.notePath = relative.isEmpty
            ? "TodayFlow.md"
            : "\(relative)/TodayFlow.md"
        #endif
    }

    private func chooseObsidianVault() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.message = "Choose your Obsidian vault folder."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        model.obsidianSettings.vaultPath = url.path
        model.obsidianSettings.vaultName = url.lastPathComponent
        if model.obsidianSettings.notePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.obsidianSettings.notePath = ObsidianSettings.defaultNotePath
        }
        model.obsidianSettings.enabled = true
        #endif
    }

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sunday"
        case 2: return "Monday"
        case 3: return "Tuesday"
        case 4: return "Wednesday"
        case 5: return "Thursday"
        case 6: return "Friday"
        default: return "Saturday"
        }
    }
}

private struct SettingsPreviewHost: View {
    @State private var model: SettingsViewModel?

    var body: some View {
        Group {
            if let model {
                SettingsView(model: model)
            } else {
                ProgressView()
            }
        }
        .task {
            let repository = InMemorySettingRepository()
            let keychain = InMemoryKeychainStore()
            let model = SettingsViewModel(repository: repository, keychain: keychain)
            await model.load()
            self.model = model
        }
    }
}

#Preview {
    SettingsPreviewHost()
}
