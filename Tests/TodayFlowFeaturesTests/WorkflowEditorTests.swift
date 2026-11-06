import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

@Suite("Workflow editor")
@MainActor
struct WorkflowEditorTests {
    @Test func deletingARuleRemovesItFromTheCanvasAndSettings() async throws {
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let today = TodayViewModel(
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: settings
        )
        await today.load()
        await today.addTray(name: "Done")
        let source = try #require(today.trays.first)
        let target = try #require(today.trays.last)
        let rule = TrayWorkflowRule(
            sourceTrayId: source.id,
            targetTrayId: target.id,
            trigger: .completed
        )
        let data = try JSONEncoder().encode([rule])
        try await settings.set(
            String(decoding: data, as: UTF8.self),
            for: SettingKeys.workflowRules
        )
        let model = WorkflowEditorModel(today: today, repository: settings)
        await model.load()
        #expect(model.rules.count == 1)

        await model.deleteRule(rule.id)

        #expect(model.rules.isEmpty)
        let raw = try #require(await settings.value(for: SettingKeys.workflowRules))
        let stored = try JSONDecoder().decode(
            [TrayWorkflowRule].self,
            from: Data(raw.utf8)
        )
        #expect(stored.isEmpty)
    }

    @Test func turningAWorkflowOnRunsItImmediately() async throws {
        let items = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let today = TodayViewModel(
            repository: items,
            linkRepository: InMemoryLinkRepository(),
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: settings
        )
        await today.load()
        await today.addTray(name: "Done")
        let source = try #require(today.trays.first)
        let target = try #require(today.trays.last)
        let task = WorkItem(
            title: "Finished report",
            status: .done,
            startAt: Date(),
            endAt: Date()
        )
        await items.seed(task)
        await today.load()
        await today.addToTray(task.id, trayId: source.id)
        let rule = TrayWorkflowRule(
            sourceTrayId: source.id,
            targetTrayId: target.id,
            trigger: .completed,
            isEnabled: false
        )
        let data = try JSONEncoder().encode([rule])
        try await settings.set(
            String(decoding: data, as: UTF8.self),
            for: SettingKeys.workflowRules
        )
        let model = WorkflowEditorModel(today: today, repository: settings)
        await model.load()
        #expect(today.tray(id: source.id)?.itemIds == [task.id])

        await model.setEnabled(rule.id, true)

        #expect(today.tray(id: source.id)?.itemIds.isEmpty == true)
        #expect(today.tray(id: target.id)?.itemIds == [task.id])
    }
}
