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
    @State private var selectedTab: SettingsTab = .general
    @State private var showResetConfirmation = false

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

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case obsidian = "Obsidian"
        case ai = "AI"
        case about = "About"

        var id: String { rawValue }
    }

    /// Monday-first, matching the way most work weeks are described.
    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    @MainActor
    public var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            Picker("Settings section", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                Form {
                    if selectedTab == .general {
                        Section("Work schedule") {
                            LabeledContent("Work hours") {
                                HStack(spacing: 6) {
                                    Picker("Start", selection: $model.calendarSettings.startHour) {
                                        ForEach(0..<24) { hour in
                                            Text(Self.hourLabel(hour)).tag(Double(hour))
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 84)

                                    Text("to")
                                        .foregroundStyle(.secondary)

                                    Picker("End", selection: $model.calendarSettings.endHour) {
                                        ForEach(0..<24) { hour in
                                            Text(Self.hourLabel(hour)).tag(Double(hour))
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 84)
                                }
                            }

                            LabeledContent("Workdays") {
                                HStack(spacing: 4) {
                                    ForEach(Self.weekdayOrder, id: \.self) { weekday in
                                        workdayChip(weekday)
                                    }
                                }
                            }

                            Text(Self.businessHoursExplanation(
                                start: Int(model.calendarSettings.startHour),
                                end: Int(model.calendarSettings.endHour),
                                weekdays: model.calendarSettings.workWeekdays
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if selectedTab == .obsidian {
                        Section("Connection") {
                            Toggle("Sync with Obsidian", isOn: $model.obsidianSettings.enabled)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Connection")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                Picker("Connection", selection: $model.obsidianSettings.mode) {
                                    Text("This Mac").tag(ObsidianSettings.Mode.local)
                                    Text("Remote").tag(ObsidianSettings.Mode.remote)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }

                            Text(model.obsidianSettings.mode == .local
                                 ? "Uses a vault folder on this Mac, including iCloud or any synced folder."
                                 : "Uses the Local REST API plugin inside Obsidian on another Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if model.obsidianSettings.mode == .local {
                            Section("Vault") {
                                LabeledContent("Vault") {
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
                                }

                                Text(
                                    model.obsidianSettings.vaultPath.isEmpty
                                        ? "No vault selected. Choose Folder… to add one."
                                        : model.obsidianSettings.vaultPath
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)

                                LabeledContent("Vault name") {
                                    TextField("", text: $model.obsidianSettings.vaultName)
                                        .textFieldStyle(.squareBorder)
                                        .accessibilityLabel("Vault name")
                                }
                                Text("Used for obsidian:// links; usually the folder name.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Section("Remote server") {
                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        Task { @MainActor in await self.model.scanObsidianLAN() }
                                    } label: {
                                        Label("Find Local REST API on LAN", systemImage: "wifi")
                                    }
                                    .disabled(model.isScanningObsidian)

                                    if model.isScanningObsidian {
                                        ProgressView()
                                            .controlSize(.small)
                                    }

                                    if let status = model.obsidianScanStatus {
                                        Text(status)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }

                                if !model.obsidianDiscoveredServers.isEmpty {
                                    Picker("Server", selection: Binding(
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
                                    TextField("", text: $model.obsidianSettings.remoteHost)
                                        .textFieldStyle(.squareBorder)
                                        .accessibilityLabel("Host")
                                }
                                Text("The remote Mac's IP or hostname, or use Find Local REST API on LAN above.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                LabeledContent("Port") {
                                    TextField(
                                        "",
                                        value: $model.obsidianSettings.remotePort,
                                        format: .number.grouping(.never)
                                    )
                                    .textFieldStyle(.squareBorder)
                                    .frame(width: 80)
                                    .accessibilityLabel("Port")
                                }

                                LabeledContent("Use HTTPS") {
                                    Toggle("Use HTTPS", isOn: $model.obsidianSettings.remoteUseHTTPS)
                                        .labelsHidden()
                                }
                                Text("Uses the plugin's self-signed certificate; TodayFlow trusts it for this connection.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                LabeledContent("API key") {
                                    SecureField("", text: $model.obsidianAPIKey)
                                        .textFieldStyle(.squareBorder)
                                        .accessibilityLabel("Obsidian API key")
                                }

                                Picker("Transport", selection: $model.obsidianSettings.remoteTransport) {
                                    ForEach(ObsidianSettings.Transport.allCases, id: \.self) { transport in
                                        Text(transport.label).tag(transport)
                                    }
                                }
                                Text("REST is the plugin's direct vault API. MCP uses its MCP endpoint; both need the same API key.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                VStack(alignment: .leading, spacing: 6) {
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

                                DisclosureGroup("Remote setup help") {
                                    Text("On the remote Obsidian: install Local REST API, set its binding host to 0.0.0.0, enable HTTP (27123) or HTTPS (27124), and copy the API key.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Link("Install Local REST API", destination: TutorialLinks.obsidianPlugin)
                                }
                            }
                        }

                        Section("Sync note") {
                            LabeledContent("Note path") {
                                HStack(spacing: 8) {
                                    TextField("", text: $model.obsidianSettings.notePath)
                                        .textFieldStyle(.squareBorder)
                                        .accessibilityLabel("Note path")
                                    if model.obsidianSettings.mode == .local {
                                        Button("Folder…") {
                                            chooseObsidianNoteFolder()
                                        }
                                        .help("Choose a folder inside the vault for the sync note")
                                    }
                                }
                            }
                            Text("Relative to the vault. In remote mode, relative to the vault open in Obsidian.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
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

                            Text("Sync now saves these settings first. Two-way sync for status, titles, tags, and due dates; new checklist lines become tasks.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Link("Obsidian guide", destination: TutorialLinks.obsidian)
                        }
                    }

                    if selectedTab == .ai {
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
                                            "Apple Intelligence is not available here. Choose Ollama, LM Studio, OpenAI, or a custom endpoint.",
                                            systemImage: "exclamationmark.triangle"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    }
                                } else {
                                    LabeledContent("Base URL") {
                                        TextField("", text: $model.aiSettings.baseURL)
                                            .textFieldStyle(.squareBorder)
                                            .accessibilityLabel("Base URL")
                                    }
                                    if model.aiSettings.provider != .openai {
                                        LabeledContent("Port") {
                                            TextField(
                                                "",
                                                value: aiPortBinding,
                                                format: .number.grouping(.never)
                                            )
                                            .textFieldStyle(.squareBorder)
                                            .frame(width: 80)
                                            .accessibilityLabel("AI server port")
                                        }
                                        Text("Use this when your server is not on its standard port; it updates the base URL above.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    LabeledContent("API key") {
                                        SecureField("", text: $model.aiSettings.apiKey)
                                            .textFieldStyle(.squareBorder)
                                            .accessibilityLabel("AI API key")
                                    }
                                    LabeledContent("Model") {
                                        HStack(spacing: 8) {
                                            TextField("", text: $model.aiSettings.model)
                                                .textFieldStyle(.squareBorder)
                                                .accessibilityLabel("Model")
                                            if model.modelCatalogAvailable {
                                                Button(model.isFetchingModels ? "Fetching…" : "Fetch models") {
                                                    Task { @MainActor in await model.fetchModels() }
                                                }
                                                .disabled(model.isFetchingModels)
                                            }
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
                            } else {
                                Text("AI is off by default. Enable it to use the AI features.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if model.aiSettings.enabled {
                            Section("AI features") {
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
                            }
                        }

                        if let onOpenAISetup {
                            Section {
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
                    }

                    if selectedTab == .about {
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

                        Section("Reset") {
                            Button(role: .destructive) {
                                showResetConfirmation = true
                            } label: {
                                Text("Reset to defaults…")
                                    .foregroundStyle(.red)
                            }
                            .disabled(model.isLoading || model.isSaving)

                            Text("Clears work hours, AI, Obsidian, and saved API keys.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section {
                            LabeledContent("Version", value: Self.appVersion)
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(maxWidth: .infinity)
            }
            .id(selectedTab)
            Divider()
            saveBar
        }
        .frame(
            minWidth: DesignTokens.Window.settings.width,
            minHeight: DesignTokens.Window.settings.height
        )
        .task { await model.load() }
        .onChange(of: model.obsidianSettings) { _, _ in
            model.clearObsidianConnectionStatus()
        }
        .onChange(of: model.obsidianAPIKey) { _, _ in
            model.clearObsidianConnectionStatus()
        }
        .confirmationDialog(
            "Reset all settings to defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Settings", role: .destructive) {
                Task { @MainActor in await model.resetToDefaults() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Work hours, AI, Obsidian, and saved API keys will be cleared. This cannot be undone.")
        }
    }

    /// Always-visible Save bar. The form itself scrolls, but Save never does,
    /// so the button cannot be missed at the bottom of a long section.
    private var saveBar: some View {
        HStack(spacing: 10) {
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                Text("Saving…")
                    .foregroundStyle(.secondary)
            } else if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(error)
            } else if model.hasUnsavedChanges {
                Label("Unsaved changes", systemImage: "circle.fill")
                    .foregroundStyle(.orange)
            } else if model.didSave {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Changes are saved when you click Save.")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Save") {
                Task { @MainActor in await model.save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .help("Save settings (⌘S)")
            .disabled(model.isLoading || model.isSaving)
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Compact business hours

    private func toggleWorkday(_ weekday: Int) {
        if model.calendarSettings.workWeekdays.contains(weekday) {
            model.calendarSettings.workWeekdays.removeAll { $0 == weekday }
        } else {
            model.calendarSettings.workWeekdays.append(weekday)
            model.calendarSettings.workWeekdays.sort()
        }
    }

    private func workdayChip(_ weekday: Int) -> some View {
        let selected = model.calendarSettings.workWeekdays.contains(weekday)
        return Button {
            toggleWorkday(weekday)
        } label: {
            Text(Self.weekdayShortName(weekday))
                .font(.caption.weight(.semibold))
                .frame(width: 34, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.weekdayName(weekday))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static func businessHoursExplanation(
        start: Int,
        end: Int,
        weekdays: [Int]
    ) -> String {
        "\(weekdaySummary(weekdays)), \(hourLabel(start))–\(hourLabel(end)). New tasks default to today's \(hourLabel(end)) on a workday, or the next workday's \(hourLabel(end)) after hours and on non-workdays. These hours guide defaults and planning; they don't block tasks."
    }

    private static func weekdaySummary(_ weekdays: [Int]) -> String {
        let selected = Set(weekdays)
        if selected == Set(1...7) { return "Every day" }
        if selected == Set(2...6) { return "Mon–Fri" }
        if selected.isEmpty { return "No workdays" }
        return weekdayOrder
            .filter { selected.contains($0) }
            .map { weekdayShortName($0) }
            .joined(separator: ", ")
    }

    private static func weekdayShortName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        default: return "Sat"
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: Bindings (manual — the stored `model` is a plain `let`)

    private var aiPortBinding: Binding<Int> {
        Binding(
            get: {
                URLComponents(string: model.aiSettings.baseURL)?.port
                    ?? Self.defaultAIPort(
                        for: model.aiSettings.provider,
                        baseURL: model.aiSettings.baseURL
                    )
            },
            set: { port in
                guard (1...65_535).contains(port),
                      var components = URLComponents(string: model.aiSettings.baseURL),
                      components.host?.isEmpty == false
                else { return }
                components.port = port
                if let url = components.url {
                    model.aiSettings.baseURL = url.absoluteString
                }
            }
        )
    }

    private static func defaultAIPort(
        for provider: AIEndpointSettings.Provider,
        baseURL: String
    ) -> Int {
        switch provider {
        case .gpuBuddy: return 8080
        case .ollama: return 11_434
        case .lmStudio: return 1_234
        case .openai, .apple: return 443
        case .custom:
            return URLComponents(string: baseURL)?.scheme?.lowercased() == "http" ? 80 : 443
        }
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
