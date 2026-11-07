import Foundation
import Observation
import TodayFlowCore

/// An error shown inside the note-path browser.
public struct ObsidianBrowserError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Model for the settings screen (driver.md §11 feature 5).
///
/// Owns the two settings groups the app persists in the `setting` store:
/// business hours (`WorkCalendarSettings`, driver.md line 49) and the AI
/// endpoint (`AIEndpointSettings`, driver.md §8). The view edits the observed
/// copies; `save()` persists both.
///
/// The AI API key is the one exception: it lives in the `KeychainStore`
/// (driver.md line 411 / NFR-10: API keys in Keychain), never in the
/// settings store.
@MainActor
@Observable
public final class SettingsViewModel {
    // MARK: Observed state

    /// Business hours. Editing these changes the `workCalendar` below, which
    /// is what computes default end dates.
    public var calendarSettings = WorkCalendarSettings() {
        didSet { noteEdited() }
    }

    /// Optional Obsidian bridge (off by default).
    public var obsidianSettings = ObsidianSettings() {
        didSet { noteEdited() }
    }
    /// Vaults registered with the Obsidian desktop app, if any.
    public private(set) var obsidianVaults: [ObsidianVault] = []
    /// Remote-mode API key (stored in the Keychain, never the settings JSON).
    public var obsidianAPIKey = "" {
        didSet { noteEdited() }
    }
    public private(set) var obsidianDiscoveredServers: [DiscoveredObsidianServer] = []
    public private(set) var isScanningObsidian = false
    public private(set) var obsidianScanStatus: String?
    public private(set) var obsidianConnectionStatus: String?

    /// AI endpoint (off by default).
    public var aiSettings = AIEndpointSettings() {
        didSet {
            noteEdited()
            // When the user picks a different provider, fill in the preset's
            // base URL — but only if the current URL is still a preset default
            // (or empty); a user-customized URL is preserved.
            guard !isApplying, aiSettings.provider != oldValue.provider else { return }
            let isPresetURL = AIEndpointSettings.Provider.allCases.contains {
                !$0.defaultBaseURL.isEmpty && $0.defaultBaseURL == oldValue.baseURL
            }
            if isPresetURL || oldValue.baseURL.isEmpty {
                aiSettings.baseURL = aiSettings.provider.defaultBaseURL
            }
        }
    }

    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var lastError: String?
    /// True when an edit has not been written to the store yet. Drives the
    /// always-visible Save bar at the bottom of Settings.
    public private(set) var hasUnsavedChanges = false
    /// True after a successful save, cleared by the next edit.
    public private(set) var didSave = false
    /// Models reported by the endpoint's `GET /models` (driver.md §8).
    public private(set) var availableModels: [String] = []
    public private(set) var isFetchingModels = false

    // MARK: Dependencies

    @ObservationIgnored private let repository: any SettingRepository
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let modelCatalog: (any AIModelCatalog)?

    /// True while `load()`/`resetToDefaults()` are applying stored values —
    /// suppresses the provider didSet side effect for programmatic writes.
    @ObservationIgnored private var isApplying = false

    public init(
        repository: any SettingRepository,
        keychain: any KeychainStore,
        calendar: Calendar = .current,
        modelCatalog: (any AIModelCatalog)? = nil
    ) {
        self.repository = repository
        self.keychain = keychain
        self.calendar = calendar
        self.modelCatalog = modelCatalog
    }

    /// True when the host supplied a model catalog (the production app does).
    public var modelCatalogAvailable: Bool { modelCatalog != nil }

    /// The `WorkCalendar` derived from the current business-hours settings —
    /// what hosts (the Today list, capture) use to compute default end dates.
    public var workCalendar: WorkCalendar {
        WorkCalendar(
            startHour: calendarSettings.startHour,
            endHour: calendarSettings.endHour,
            workWeekdays: Set(calendarSettings.workWeekdays),
            calendar: calendar
        )
    }

    // MARK: Actions

    /// Loads both groups from the store; an absent or corrupt stored value
    /// falls back to the group's defaults (a bad value must never break the UI).
    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        isApplying = true
        defer { isApplying = false }

        calendarSettings = Self.calendarSettings(from: await repository.value(for: SettingKeys.workCalendar))
        aiSettings = Self.aiSettings(from: await repository.value(for: SettingKeys.aiEndpoint))
        obsidianSettings = Self.obsidianSettings(from: await repository.value(for: SettingKeys.obsidian))
        obsidianVaults = Self.discoverObsidianVaults()
        await applyKeychainKey()
    }

    /// Reconciles the in-memory API key with the Keychain (driver.md line
    /// 411 / NFR-10). The Keychain wins if it holds a key; a non-empty key
    /// still in the stored JSON (a pre-6.3 store) is migrated to the Keychain
    /// on first load. If the Keychain is unavailable, the stored value is
    /// kept in memory (it is still in the settings store, so nothing is lost)
    /// and the migration retries on the next load.
    private func applyKeychainKey() async {
        let storedKey = aiSettings.apiKey
        if let keychainKey = await keychain.read(KeychainKeys.aiAPIKey), !keychainKey.isEmpty {
            aiSettings.apiKey = keychainKey
        } else if !storedKey.isEmpty {
            _ = try? await keychain.write(storedKey, for: KeychainKeys.aiAPIKey)
        }
        obsidianAPIKey = await keychain.read(KeychainKeys.obsidianAPIKey) ?? ""
    }

    /// Persists both groups. The API key goes to the Keychain first (an
    /// empty key deletes the entry); the settings store keeps a redacted
    /// copy. If the Keychain write fails, the store is left untouched and
    /// `lastError` is set.
    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        didSave = false
        defer { isSaving = false }
        lastError = nil
        do {
            if aiSettings.apiKey.isEmpty {
                try await keychain.delete(KeychainKeys.aiAPIKey)
            } else {
                try await keychain.write(aiSettings.apiKey, for: KeychainKeys.aiAPIKey)
            }
            if obsidianAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try await keychain.delete(KeychainKeys.obsidianAPIKey)
            } else {
                try await keychain.write(
                    obsidianAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    for: KeychainKeys.obsidianAPIKey
                )
            }
            var stored = aiSettings
            stored.apiKey = ""
            try await repository.set(
                try Self.encode(calendarSettings),
                for: SettingKeys.workCalendar
            )
            try await repository.set(
                try Self.encode(stored),
                for: SettingKeys.aiEndpoint
            )
            try await repository.set(
                try Self.encode(obsidianSettings),
                for: SettingKeys.obsidian
            )
            hasUnsavedChanges = false
            didSave = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Marks the form dirty for the always-visible Save bar. Programmatic
    /// writes during `load()`/`resetToDefaults()` do not count as edits.
    private func noteEdited() {
        guard !isApplying else { return }
        hasUnsavedChanges = true
        didSave = false
        lastError = nil
    }

    /// Clears the last Test connection result when the remote address or key
    /// changes, so a stale "Connected" message cannot describe new input.
    public func clearObsidianConnectionStatus() {
        obsidianConnectionStatus = nil
    }

    /// Lists the saved endpoint's models (driver.md §8 "Fetch models"). The
    /// catalog reads Settings + Keychain, so Save first after changing the
    /// base URL or API key.
    public func fetchModels() async {
        guard let modelCatalog, !isFetchingModels else { return }
        isFetchingModels = true
        defer { isFetchingModels = false }
        lastError = nil

        do {
            // Use the current edits so Fetch works before Save.
            availableModels = try await modelCatalog.listModels(for: aiSettings)
        } catch {
            availableModels = []
            lastError = error.localizedDescription
        }
    }

    /// Scans the LAN for Obsidian Local REST API servers on the plugin's two
    /// standard ports. The API key still needs to be copied once.
    public func scanObsidianLAN() async {
        guard !isScanningObsidian else { return }
        isScanningObsidian = true
        obsidianScanStatus = nil
        defer { isScanningObsidian = false }

        let found = await ObsidianLANDiscovery.scan()
        obsidianDiscoveredServers = found
        if found.isEmpty {
            obsidianScanStatus = "No Local REST API server found. Install the plugin on the remote Obsidian, bind it to 0.0.0.0, and enable HTTP or HTTPS."
        } else {
            obsidianScanStatus = "Found \(found.count) Local REST API server\(found.count == 1 ? "" : "s"). Select one, then paste its API key."
            if obsidianSettings.remoteHost.isEmpty, let first = found.first {
                applyObsidianServer(first)
            }
        }
    }

    public func applyObsidianServer(_ server: DiscoveredObsidianServer) {
        obsidianSettings.mode = .remote
        obsidianSettings.remoteHost = server.host
        obsidianSettings.remotePort = server.port
        obsidianSettings.remoteUseHTTPS = server.useHTTPS
        obsidianSettings.remoteDisplayName = server.displayName
        obsidianSettings.enabled = true
        obsidianConnectionStatus = nil
    }

    /// Verifies the current remote host/port and API key without saving.
    public func testObsidianConnection() async {
        obsidianConnectionStatus = nil
        guard let transport = makeRemoteTransport() else {
            obsidianConnectionStatus = "Enter a remote host and port first."
            return
        }
        do {
            try await transport.verify()
            let name = obsidianSettings.remoteDisplayName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let address = "\(obsidianSettings.sanitizedRemoteHost):\(obsidianSettings.remotePort)"
            obsidianConnectionStatus = name.isEmpty
                ? "Connected via \(obsidianSettings.remoteTransport.label) to \(address)."
                : "Connected via \(obsidianSettings.remoteTransport.label) to \(name) at \(address)."
        } catch {
            obsidianConnectionStatus = error.localizedDescription
        }
    }

    private func makeRemoteTransport() -> (any ObsidianRemoteTransport)? {
        switch obsidianSettings.remoteTransport {
        case .rest:
            return ObsidianRemoteClient(
                settings: obsidianSettings,
                apiKey: obsidianAPIKey
            )
        case .mcp:
            return ObsidianMCPClient(
                settings: obsidianSettings,
                apiKey: obsidianAPIKey
            )
        }
    }

    /// Lists one folder for the note-path browser. Local vaults are read from
    /// disk; remote vaults ask the plugin (REST or MCP) for a directory listing.
    public func obsidianBrowserEntries(
        at path: String
    ) async -> Result<[ObsidianVaultEntry], ObsidianBrowserError> {
        let relative = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if obsidianSettings.mode == .local {
            guard let vaultURL = obsidianSettings.vaultURL else {
                return .failure(ObsidianBrowserError("Choose a vault first."))
            }
            let directory = relative.isEmpty
                ? vaultURL
                : vaultURL.appendingPathComponent(relative, isDirectory: true)
            do {
                // Use the path-based enumeration for iCloud/FileProvider
                // vaults; the URL-based variant can report an empty folder
                // before the provider has materialized it.
                let names = try FileManager.default.contentsOfDirectory(
                    atPath: directory.path
                )
                let entries = names.compactMap { name -> ObsidianVaultEntry? in
                    guard !name.hasPrefix(".") else { return nil }
                    let url = directory.appendingPathComponent(name)
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(
                        atPath: url.path,
                        isDirectory: &isDirectory
                    ) else { return nil }
                    if !isDirectory.boolValue, url.pathExtension.lowercased() != "md" {
                        return nil
                    }
                    return ObsidianVaultEntry(
                        path: relative.isEmpty ? name : "\(relative)/\(name)",
                        name: name,
                        isDirectory: isDirectory.boolValue
                    )
                }
                return .success(Self.sortedObsidianEntries(entries))
            } catch {
                return .failure(ObsidianBrowserError(error.localizedDescription))
            }
        }

        guard let transport = makeRemoteTransport() else {
            return .failure(ObsidianBrowserError("Enter a remote host and port first."))
        }
        do {
            let names = try await transport.list(relative)
            let entries = names.compactMap { value -> ObsidianVaultEntry? in
                let isDirectory = value.hasSuffix("/")
                let name = isDirectory ? String(value.dropLast()) : value
                if !isDirectory, !name.lowercased().hasSuffix(".md") {
                    return nil
                }
                return ObsidianVaultEntry(
                    path: relative.isEmpty ? name : "\(relative)/\(name)",
                    name: name,
                    isDirectory: isDirectory
                )
            }
            return .success(Self.sortedObsidianEntries(entries))
        } catch {
            return .failure(ObsidianBrowserError(error.localizedDescription))
        }
    }

    private static func sortedObsidianEntries(
        _ entries: [ObsidianVaultEntry]
    ) -> [ObsidianVaultEntry] {
        entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Restores all groups to their defaults and persists them.
    public func resetToDefaults() async {
        isApplying = true
        calendarSettings = WorkCalendarSettings()
        aiSettings = AIEndpointSettings()
        obsidianSettings = ObsidianSettings()
        obsidianAPIKey = ""
        isApplying = false
        await save()
    }

    // MARK: Encoding

    private static func calendarSettings(from value: String?) -> WorkCalendarSettings {
        guard let value,
              let decoded = try? JSONDecoder().decode(WorkCalendarSettings.self, from: Data(value.utf8))
        else {
            return WorkCalendarSettings()
        }
        return decoded
    }

    private static func discoverObsidianVaults() -> [ObsidianVault] {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        guard let url = support?
            .appendingPathComponent("obsidian", isDirectory: true)
            .appendingPathComponent("obsidian.json"),
              let data = try? Data(contentsOf: url),
              let json = String(data: data, encoding: .utf8)
        else { return [] }
        return ObsidianVaultRegistry.parse(json)
    }

    private static func obsidianSettings(from value: String?) -> ObsidianSettings {
        guard let value,
              let decoded = try? JSONDecoder().decode(ObsidianSettings.self, from: Data(value.utf8))
        else {
            return ObsidianSettings()
        }
        return decoded
    }

    private static func aiSettings(from value: String?) -> AIEndpointSettings {
        guard let value,
              let decoded = try? JSONDecoder().decode(AIEndpointSettings.self, from: Data(value.utf8))
        else {
            return AIEndpointSettings()
        }
        return decoded
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }
}
