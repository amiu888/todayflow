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
}
