#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowDesign

/// Manual helper used to refresh the screenshots in docs/tutorials.
/// Run with `TODAYFLOW_WRITE_TUTORIAL_IMAGES=1 swift test --filter TutorialSnapshotTests`.
@Suite("Tutorial screenshots")
@MainActor
struct TutorialSnapshotTests {
    @Test func writeTutorialImages() async throws {
        guard ProcessInfo.processInfo.environment["TODAYFLOW_WRITE_TUTORIAL_IMAGES"] == "1"
        else { return }
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/tutorials/images", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // Today panel
        let items = InMemoryWorkItemRepository()
        let now = Date()
        let seed = [
            WorkItem(title: "Review the quarterly roadmap and send feedback", priority: .urgent, startAt: now, endAt: now.addingTimeInterval(3600), displayOrder: "a", tags: ["launch", "Q4"]),
            WorkItem(title: "Prepare customer notes", priority: .high, startAt: now, endAt: now.addingTimeInterval(7200), displayOrder: "b"),
            WorkItem(title: "Ship the release", priority: .normal, startAt: now, endAt: now.addingTimeInterval(10800), displayOrder: "c"),
        ]
        for item in seed { await items.seed(item) }
        let today = TodayViewModel(
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository()
        )
        await today.load()
        for name in ["Now", "Waiting", "Client A", "Client B"] {
            await today.addTray(name: name)
        }
        if let tray = today.trays.first, let item = seed.first {
            await today.addToTray(item.id, trayId: tray.id)
        }
        await today.load()
        let windowActions = WindowMenuActions(
            toggleDocking: {},
            toggleAllDesktops: {},
            toggleMiniCalendar: {},
            showMiniDay: {},
            showMiniWeek: {},
            pinMiniCalendar: { _ in }
        )
        let aiActions = AIActions(
            ask: {},
            plan: {},
            configure: {},
            settings: {}
        )
        let todayView = TodayView(
            model: today,
            onOpenTask: { _ in },
            onFocusTask: { _ in },
            onNewTask: {},
            onOpenUpcoming: {},
            onShowMiniCalendar: {},
            onOpenTray: { _ in },
            onOpenContacts: {},
            onOpenWorkflows: {},
            onDockToApp: { _, _ in false },
            onUndockApp: {},
            windowActions: windowActions,
            aiActions: aiActions
        )
        try await render(
            todayView.frame(width: 360, height: 640),
            size: CGSize(width: 360, height: 640),
            to: root.appendingPathComponent("today-panel.png")
        )
        try await render(
            todayView.frame(width: 260, height: 640),
            size: CGSize(width: 260, height: 640),
            to: root.appendingPathComponent("today-panel-narrow.png")
        )

        // Task detail with contacts
        let contactsRepo = InMemoryContactRepository()
        let jane = Contact(
            firstName: "Jane",
            lastName: "Smith",
            company: "Acme",
            emails: ["jane@acme.com"]
        )
        try await contactsRepo.save(jane)
        let detailItem = WorkItem(title: "Follow up with Jane about the contract", priority: .high, startAt: now, endAt: now.addingTimeInterval(3600), tags: ["client", "contract"])
        await items.seed(detailItem)
        try await contactsRepo.addContact(jane.id, toTask: detailItem.id)
        let detail = DetailViewModel(
            itemId: detailItem.id,
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            contactRepository: contactsRepo
        )
        await detail.load()
        try await render(
            DetailView(model: detail).frame(width: 720, height: 640),
            size: CGSize(width: 720, height: 640),
            to: root.appendingPathComponent("task-contact.png")
        )

        // Workflow editor
        let workflowSettings = InMemorySettingRepository()
        let sourceTray = try #require(today.trays.first)
        let targetTray = try #require(today.trays.dropFirst().first)
        let rule = TrayWorkflowRule(
            sourceTrayId: sourceTray.id,
            targetTrayId: targetTray.id,
            trigger: .completed
        )
        let ruleData = try JSONEncoder().encode([rule])
        try await workflowSettings.set(
            String(decoding: ruleData, as: UTF8.self),
            for: SettingKeys.workflowRules
        )
        let workflowModel = WorkflowEditorModel(
            today: today,
            repository: workflowSettings
        )
        await workflowModel.load()
        try await render(
            WorkflowEditorView(model: workflowModel).frame(width: 920, height: 620),
            size: CGSize(width: 920, height: 620),
            to: root.appendingPathComponent("workflow-editor.png")
        )

        // AI setup with a detected local server
        let settings = InMemorySettingRepository()
        let ai = AIOnboardingViewModel(
            installer: TutorialInstaller(),
            settings: settings,
            keychain: InMemoryKeychainStore(),
            appleAvailable: true,
            discovering: TutorialDiscovery()
        )
        await ai.refreshServer()
        await ai.scanLocalAI()
        try await render(
            AIOnboardingView(model: ai).frame(width: 760, height: 620),
            size: CGSize(width: 760, height: 620),
            to: root.appendingPathComponent("ai-setup.png")
        )
    }

    private func render<V: View>(_ view: V, size: CGSize, to url: URL) async throws {
        let host = NSHostingView(
            rootView: view
                .environment(\.colorScheme, .dark)
                .background(DesignTokens.Palette.background)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}

private struct TutorialInstaller: LocalModelInstaller {
    func isRunning() async -> Bool { true }
    func installedModelNames() async throws -> [String] { [] }
    func download(_ model: LocalAIModel) -> AsyncThrowingStream<LocalModelDownloadProgress, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private struct TutorialDiscovery: LocalAIDiscovering {
    func scan() async -> [LocalAICandidate] {
        [
            LocalAICandidate(
                id: "http://127.0.0.1:1234/v1",
                name: "LM Studio",
                baseURL: URL(string: "http://127.0.0.1:1234/v1")!,
                provider: .lmStudio,
                models: ["qwen3-8b", "llama-3.2-3b"]
            )
        ]
    }
}
#endif
