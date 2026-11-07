import Foundation
import Observation
import TodayFlowCore

/// Metadata for an optional local model. Sizes are shown before the user
/// commits so the download is never a surprise.
public struct LocalAIModel: Sendable, Hashable {
    public let ollamaName: String
    public let displayName: String
    public let downloadBytes: Int64
    public let diskBytes: Int64
    public let memoryFootnote: String
    public let license: String

    public init(
        ollamaName: String,
        displayName: String,
        downloadBytes: Int64,
        diskBytes: Int64,
        memoryFootnote: String,
        license: String
    ) {
        self.ollamaName = ollamaName
        self.displayName = displayName
        self.downloadBytes = downloadBytes
        self.diskBytes = diskBytes
        self.memoryFootnote = memoryFootnote
        self.license = license
    }

    public var downloadSizeText: String { Self.sizeText(downloadBytes) }
    public var diskSizeText: String { Self.sizeText(diskBytes) }

    public static let tiny = LocalAIModel(
        ollamaName: AIEndpointSettings.tinyLocalModel,
        displayName: AIEndpointSettings.tinyLocalModelDisplayName,
        downloadBytes: AIEndpointSettings.tinyLocalModelDownloadBytes,
        diskBytes: AIEndpointSettings.tinyLocalModelDiskBytes,
        memoryFootnote: AIEndpointSettings.tinyLocalModelMemoryFootnote,
        license: "Apache 2.0"
    )

    public static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// One progress event from Ollama's streaming `/api/pull` response.
public struct LocalModelDownloadProgress: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case preparing
        case downloading
        case verifying
        case writing
        case done
    }

    public let phase: Phase
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let status: String

    public init(
        phase: Phase,
        completedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        status: String = ""
    ) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.status = status
    }

    public var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    public var percent: Int {
        Int(((fraction ?? 0) * 100).rounded())
    }
}

/// The small seam the onboarding view uses. Production talks to the local
/// Ollama server; tests use an in-memory fake.
public enum LocalModelInstallError: LocalizedError, Equatable {
    case incompleteDownload

    public var errorDescription: String? {
        switch self {
        case .incompleteDownload:
            return "The model download didn’t finish. Check your connection and try again."
        }
    }
}

public protocol LocalModelInstaller: Sendable {
    func isRunning() async -> Bool
    func installedModelNames() async throws -> [String]
    func download(_ model: LocalAIModel) -> AsyncThrowingStream<LocalModelDownloadProgress, Error>
}

/// One local OpenAI-compatible server found during setup.
public struct LocalAICandidate: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let baseURL: URL
    public let provider: AIEndpointSettings.Provider
    public let models: [String]

    public init(
        id: String,
        name: String,
        baseURL: URL,
        provider: AIEndpointSettings.Provider,
        models: [String]
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.provider = provider
        self.models = models
    }
}

/// Scans well-known localhost ports for Ollama, LM Studio, llama.cpp, LocalAI,
/// vLLM, and similar OpenAI-compatible servers.
public protocol LocalAIDiscovering: Sendable {
    func scan() async -> [LocalAICandidate]
    func scan(customPort: Int?) async -> [LocalAICandidate]
}

public extension LocalAIDiscovering {
    /// Hosts that do not implement custom-port discovery fall back to the
    /// standard scan.
    func scan(customPort: Int?) async -> [LocalAICandidate] {
        await scan()
    }
}

public struct NoLocalAIDiscovery: LocalAIDiscovering {
    public init() {}
    public func scan() async -> [LocalAICandidate] { [] }
}

/// First-run AI setup: Apple Intelligence (0 MB), a detected local server, a
/// tiny local model (533 MB through Ollama), or skip. Nothing is downloaded
/// until the user explicitly chooses, and every option can be changed later
/// in Settings.
@MainActor
@Observable
public final class AIOnboardingViewModel {
    public enum ServerState: Equatable, Sendable {
        case checking
        case ready(installedModel: Bool)
        case notRunning
    }

    public enum DownloadState: Equatable, Sendable {
        case idle
        case downloading(LocalModelDownloadProgress)
        case completed
        case failed(String)
    }

    public let appleAvailable: Bool
    public let localModel: LocalAIModel

    public private(set) var serverState: ServerState = .checking
    public private(set) var downloadState: DownloadState = .idle
    public private(set) var lastError: String?
    public private(set) var isApplying = false
    public private(set) var configuredOption: Option?
    public private(set) var configuredModelName: String?
    public private(set) var discovered: [LocalAICandidate] = []
    public private(set) var selectedModels: [String: String] = [:]
    public private(set) var isScanning = false
    /// Optional non-standard port to probe in addition to the usual ports.
    public var customScanPort = ""

    /// Set by the host window: called after a successful setup or a skip.
    @ObservationIgnored public var onFinish: (@MainActor () -> Void)?
    /// Opens the installed Ollama app, or its download page when absent.
    @ObservationIgnored public var onOpenOllama: (@MainActor () -> Void)?
    @ObservationIgnored public var onGetOllama: (@MainActor () -> Void)?

    @ObservationIgnored private let installer: any LocalModelInstaller
    @ObservationIgnored private let discovering: any LocalAIDiscovering
    @ObservationIgnored private let settings: any SettingRepository
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadToken = UUID()

    public enum Option: String, Sendable {
        case apple
        case local
    }

    public init(
        installer: any LocalModelInstaller,
        settings: any SettingRepository,
        keychain: any KeychainStore,
        appleAvailable: Bool,
        localModel: LocalAIModel = .tiny,
        discovering: any LocalAIDiscovering = NoLocalAIDiscovery()
    ) {
        self.installer = installer
        self.discovering = discovering
        self.settings = settings
        self.keychain = keychain
        self.appleAvailable = appleAvailable
        self.localModel = localModel
    }

    public var isDownloading: Bool {
        if case .downloading = downloadState { return true }
        return false
    }

    public var isBusy: Bool {
        isApplying || isDownloading
    }

    /// Looks for local AI software on its common ports. Safe to call on every
    /// setup window appearance and from the "Scan again" button.
    public func scanLocalAI() async {
        guard !isScanning else { return }
        let trimmed = customScanPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = trimmed.isEmpty ? nil : Int(trimmed)
        if !trimmed.isEmpty, port == nil || !(1...65_535).contains(port!) {
            lastError = "Enter a port between 1 and 65535."
            return
        }
        isScanning = true
        lastError = nil
        defer { isScanning = false }
        discovered = await discovering.scan(customPort: port)
        for candidate in discovered where selectedModels[candidate.id] == nil {
            selectedModels[candidate.id] = candidate.models.first
        }
    }

    /// Configures the app to use an already-running local server and marks
    /// setup complete. No download is performed.
    public func selectModel(_ model: String, for candidate: LocalAICandidate) {
        selectedModels[candidate.id] = model
    }

    public func useDiscovered(_ candidate: LocalAICandidate) async {
        guard !isBusy else { return }
        let model = selectedModels[candidate.id] ?? candidate.models.first ?? ""
        guard !model.isEmpty else {
            lastError = "Choose a model for \(candidate.name)."
            return
        }
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        let saved = await save(
            provider: candidate.provider,
            baseURL: candidate.baseURL.absoluteString,
            model: model,
            features: AIFeatures.all,
            timeout: 120
        )
        guard saved else { return }
        configuredOption = .local
        configuredModelName = "\(candidate.name) · \(model)"
        downloadState = .completed
        await markComplete()
    }

    /// Checks whether Ollama is reachable and whether the tiny model is
    /// already present, so the card can say "Download" or "Enable".
    public func refreshServer() async {
        guard !isDownloading else { return }
        serverState = .checking
        guard await installer.isRunning() else {
            serverState = .notRunning
            return
        }
        let names = (try? await installer.installedModelNames()) ?? []
        serverState = .ready(
            installedModel: names.contains(localModel.ollamaName)
        )
    }

    /// Starts the explicit model download. The first click on the local card
    /// is the consent for the 533 MB transfer.
    public func downloadLocalModel() {
        guard downloadTask == nil else { return }
        lastError = nil
        let token = UUID()
        downloadToken = token
        downloadTask = Task { [weak self] in
            await self?.runDownload(token: token)
            guard let self, self.downloadToken == token else { return }
            self.downloadTask = nil
        }
    }

    public func cancelDownload() {
        // Invalidate the old task first: its cancellation handler must not
        // clobber a download the user starts immediately afterwards.
        downloadToken = UUID()
        downloadTask?.cancel()
        downloadTask = nil
        if case .downloading = downloadState {
            downloadState = .idle
        }
    }

    public func enableLocalModel() async {
        guard !isBusy else { return }
        switch serverState {
        case .checking, .notRunning:
            await refreshServer()
            if case .notRunning = serverState {
                lastError = "Ollama isn’t running. Open it, then check again."
                return
            }
            if case .ready(false) = serverState {
                downloadLocalModel()
                return
            }
        case .ready(let installed) where !installed:
            downloadLocalModel()
            return
        default:
            break
        }
        await configureLocal()
    }

    public func enableAppleIntelligence() async {
        guard appleAvailable, !isBusy else { return }
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        let saved = await save(
            provider: .apple,
            baseURL: "",
            model: localModel.ollamaName,
            features: [AIFeatures.summarizeEmail],
            timeout: 20
        )
        guard saved else { return }
        configuredOption = .apple
        configuredModelName = "Apple Intelligence"
        await markComplete()
    }

    public func skip() async {
        cancelDownload()
        await markComplete()
        onFinish?()
    }

    public func finish() {
        onFinish?()
    }

    /// Closing the setup window counts as "seen"; it must not reappear on the
    /// next launch. The choice can still be changed in Settings.
    public func markComplete() async {
        try? await settings.set("true", for: SettingKeys.aiSetupComplete)
    }

    public func openOllama() {
        onOpenOllama?()
    }

    public func getOllama() {
        onGetOllama?()
    }

    // MARK: - Private

    private func runDownload(token: UUID) async {
        guard token == downloadToken else { return }
        if case .checking = serverState {
            await refreshServer()
        }
        if case .notRunning = serverState {
            await refreshServer()
        }
        guard token == downloadToken else { return }
        if case .notRunning = serverState {
            downloadState = .failed("Ollama isn’t running.")
            lastError = "Ollama isn’t running. Open it, then try again."
            return
        }
        if case .ready(true) = serverState {
            await configureLocal()
            return
        }

        downloadState = .downloading(
            LocalModelDownloadProgress(phase: .preparing, status: "Preparing…")
        )
        do {
            var finished = false
            for try await progress in installer.download(localModel) {
                try Task.checkCancellation()
                guard token == downloadToken else { return }
                downloadState = .downloading(progress)
                if progress.phase == .done { finished = true }
            }
            try Task.checkCancellation()
            guard token == downloadToken else { return }
            if !finished {
                // A truncated stream may still have installed the model.
                let names = (try? await installer.installedModelNames()) ?? []
                guard names.contains(localModel.ollamaName) else {
                    throw LocalModelInstallError.incompleteDownload
                }
            }
            await configureLocal()
        } catch is CancellationError {
            guard token == downloadToken else { return }
            downloadState = .idle
        } catch {
            guard token == downloadToken else { return }
            downloadState = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func configureLocal() async {
        isApplying = true
        lastError = nil
        defer { isApplying = false }
        let saved = await save(
            provider: .ollama,
            baseURL: AIEndpointSettings.Provider.ollama.defaultBaseURL,
            model: localModel.ollamaName,
            features: AIFeatures.all,
            timeout: 120
        )
        guard saved else { return }
        configuredOption = .local
        configuredModelName = localModel.displayName
        downloadState = .completed
        await markComplete()
    }

    private func save(
        provider: AIEndpointSettings.Provider,
        baseURL: String,
        model: String,
        features: [String],
        timeout: Double
    ) async -> Bool {
        let settingsModel = SettingsViewModel(
            repository: settings,
            keychain: keychain
        )
        // Preserve business hours and any unrelated stored values.
        await settingsModel.load()
        settingsModel.aiSettings.enabled = true
        settingsModel.aiSettings.provider = provider
        settingsModel.aiSettings.baseURL = baseURL
        settingsModel.aiSettings.model = model
        settingsModel.aiSettings.enabledFeatures = features
        settingsModel.aiSettings.sendAttachmentText = false
        settingsModel.aiSettings.timeoutSeconds = timeout
        // Keep any existing Keychain API key: switching to a local provider
        // must not erase a key the user may want when switching back.
        await settingsModel.save()
        if let error = settingsModel.lastError {
            lastError = error
            return false
        }
        return true
    }
}
