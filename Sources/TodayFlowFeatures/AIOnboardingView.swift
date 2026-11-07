import SwiftUI
import TodayFlowDesign

/// First-run AI choice. The model download is opt-in and the card states the
/// download, disk, and memory footprint before the button can be pressed.
public struct AIOnboardingView: View {
    @Bindable private var model: AIOnboardingViewModel

    public init(model: AIOnboardingViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    worksWithoutAI
                    if let configured = model.configuredModelName {
                        Label("AI is ready · \(configured)", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(DesignTokens.Palette.success)
                    }
                    detectedLocalAI
                    HStack(alignment: .top, spacing: 14) {
                        appleCard
                        localCard
                    }
                    if let error = model.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(DesignTokens.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Nothing is downloaded until you choose an option. You can change or remove AI later in Settings → AI.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .background(DesignTokens.Palette.background)
        .task {
            await model.refreshServer()
            await model.scanLocalAI()
        }
        .accessibilityIdentifier("ai-setup-window")
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignTokens.Palette.gradient)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Set up AI")
                    .font(.title2.weight(.semibold))
                Text("Optional. Choose what runs on this Mac — or skip for now.")
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var worksWithoutAI: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.Palette.success)
            VStack(alignment: .leading, spacing: 3) {
                Text("TodayFlow works fully without AI")
                    .font(.callout.weight(.semibold))
                Text("Tasks, trays, contacts, reminders, search, and imports never depend on a model or network request.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Palette.success.opacity(0.08))
        )
    }

    @ViewBuilder
    private var detectedLocalAI: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Detected on this Mac")
                    .font(.callout.weight(.semibold))
                if model.isScanning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                    TextField("8000", text: $model.customScanPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("Custom AI server port")
                        .onSubmit {
                            Task { await model.scanLocalAI() }
                        }
                    Button("Scan") {
                        Task { await model.scanLocalAI() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
                    .disabled(model.isScanning || model.isApplying)
                    .accessibilityIdentifier("ai-setup-scan")
                }
            }

            if model.discovered.isEmpty {
                Text("No local AI server found on Ollama (11434), LM Studio (1234), llama.cpp/GPU Buddy (8080), vLLM (8000), text-generation-webui (5000), or Jan (1337). Start one and scan again, enter its port above, or use the tiny model below.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.discovered) { candidate in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.name)
                                .font(.callout.weight(.semibold))
                            Text(candidate.baseURL.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if candidate.models.count > 1 {
                            Picker("", selection: Binding(
                                get: {
                                    model.selectedModels[candidate.id]
                                        ?? candidate.models.first
                                        ?? ""
                                },
                                set: { model.selectModel($0, for: candidate) }
                            )) {
                                ForEach(candidate.models, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 190)
                        } else {
                            Text(candidate.models.first ?? "")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.Palette.textSecondary)
                                .lineLimit(1)
                        }
                        Button("Use") {
                            Task { await model.useDiscovered(candidate) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("ai-setup-use-\(candidate.name)")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DesignTokens.Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var appleCard: some View {
        optionCard(
            icon: "apple.logo",
            iconColor: DesignTokens.Palette.textPrimary,
            title: "Apple Intelligence",
            subtitle: "Uses the built-in system model. No download and no API key.",
            badge: model.appleAvailable ? "0 MB" : "Unavailable"
        ) {
            footprintRow("Download", "0 MB")
            footprintRow("Memory", "Managed by macOS")
            footprintRow("Privacy", "On-device")
            Spacer(minLength: 0)
            if model.appleAvailable {
                if model.configuredOption == .apple {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.Palette.success)
                } else {
                    Button {
                        Task { await model.enableAppleIntelligence() }
                    } label: {
                        Text("Use Apple Intelligence")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("ai-setup-apple")
                }
            } else {
                Text("Not available on this Mac. Choose the tiny local model or set up a custom endpoint in Settings.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var localCard: some View {
        optionCard(
            icon: "cpu",
            iconColor: DesignTokens.Palette.accent,
            title: "Tiny local model",
            subtitle: "\(model.localModel.displayName) · Q4 · \(model.localModel.license). Runs privately through Ollama.",
            badge: "Recommended"
        ) {
            footprintRow("Download", model.localModel.downloadSizeText)
            footprintRow("Disk after install", model.localModel.diskSizeText)
            footprintRow("Memory", model.localModel.memoryFootnote)
            Spacer(minLength: 0)
            localCardAction
        }
    }

    @ViewBuilder
    private var localCardAction: some View {
        switch model.downloadState {
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress.fraction ?? 0)
                HStack {
                    Text(downloadLabel(progress))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .monospacedDigit()
                    Spacer()
                    Button("Cancel") { model.cancelDownload() }
                        .controlSize(.small)
                }
            }
            .accessibilityIdentifier("ai-setup-progress")

        case .completed:
            VStack(alignment: .leading, spacing: 8) {
                Label("AI is ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Palette.success)
                Text("\(model.configuredModelName ?? model.localModel.displayName) is configured in Settings and will start automatically when you use an AI feature.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("ai-setup-complete")

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.downloadLocalModel() }
                    .buttonStyle(.bordered)
            }

        case .idle:
            switch model.serverState {
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking Ollama…")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                }

            case .notRunning:
                VStack(alignment: .leading, spacing: 8) {
                    Label("Ollama isn’t running", systemImage: "exclamationmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.Palette.warning)
                    Text("The model runs through Ollama. Open it, or install it first (the Ollama app adds about 665 MB). Then check again.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Open Ollama") { model.openOllama() }
                            .buttonStyle(.borderedProminent)
                        Button("Get Ollama") { model.getOllama() }
                            .buttonStyle(.bordered)
                        Button("Check again") {
                            Task { await model.refreshServer() }
                        }
                        .buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }

            case .ready(let installed):
                if installed {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Model already downloaded", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(DesignTokens.Palette.success)
                        Button {
                            Task { await model.enableLocalModel() }
                        } label: {
                            Text("Enable local AI").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("ai-setup-local-enable")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            model.downloadLocalModel()
                        } label: {
                            Text("Download \(model.localModel.downloadSizeText)")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy)
                        .accessibilityIdentifier("ai-setup-local-download")
                        Text("One-time download through Ollama. No account, no API key, no cloud request.")
                            .font(.caption2)
                            .foregroundStyle(DesignTokens.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.configuredOption == nil {
                Button("Not now") {
                    Task { await model.skip() }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("ai-setup-skip")
            }
            Spacer()
            Link("Tutorials", destination: TutorialLinks.index)
                .font(.caption)
            Text("Settings → AI")
                .font(.caption)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            if model.configuredOption != nil {
                Button("Done") { model.finish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("ai-setup-done")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func optionCard<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        badge: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.headline)
                        Spacer()
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(DesignTokens.Palette.accentSoft)
                            )
                            .foregroundStyle(DesignTokens.Palette.accent)
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignTokens.Palette.hairline, lineWidth: 1)
        )
    }

    private func footprintRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(DesignTokens.Palette.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func downloadLabel(_ progress: LocalModelDownloadProgress) -> String {
        switch progress.phase {
        case .preparing:
            return "Preparing download…"
        case .verifying:
            return "Verifying model…"
        case .writing:
            return "Finishing install…"
        case .done:
            return "Download complete"
        case .downloading:
            if progress.totalBytes > 0 {
                let done = LocalAIModel.sizeText(progress.completedBytes)
                let total = LocalAIModel.sizeText(progress.totalBytes)
                return "\(progress.percent)% · \(done) of \(total)"
            }
            return "Downloading \(LocalAIModel.sizeText(progress.completedBytes))…"
        }
    }
}
