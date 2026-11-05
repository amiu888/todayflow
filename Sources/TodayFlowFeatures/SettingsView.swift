import SwiftUI
import TodayFlowCore
import TodayFlowDesign
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The settings window (driver.md §11 feature 5): business hours and the
/// AI endpoint (driver.md §8).
public struct SettingsView: View {
    public let model: SettingsViewModel

    public init(model: SettingsViewModel) {
        self.model = model
    }

    /// For hosts that only know the repositories (used by the 6-Mac app layer).
    @MainActor
    public init(
        repository: any SettingRepository,
        keychain: any KeychainStore,
        calendar: Calendar = .current,
        modelCatalog: (any AIModelCatalog)? = nil
    ) {
        model = SettingsViewModel(
            repository: repository,
            keychain: keychain,
            calendar: calendar,
            modelCatalog: modelCatalog
        )
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
                    ForEach(AIFeatures.all, id: \.self) { feature in
                        Toggle(AIFeatures.label(for: feature), isOn: featureBinding(feature))
                    }
                } else {
                    Text("AI is off by default. Enable it to use the AI features.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
