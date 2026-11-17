import Foundation
import Testing
import TodayFlowCore
import TodayFlowFeatures

/// The All Tasks window's working-tray filter and badges.
@MainActor
struct AllTasksViewModelTests {
    private func makeItem(_ title: String, status: Status = .todo) -> WorkItem {
        WorkItem(
            kind: .task,
            title: title,
            status: status,
            startAt: Date(timeIntervalSince1970: 1_780_000_000),
            endAt: Date(timeIntervalSince1970: 1_780_003_600),
            displayOrder: "a"
        )
    }

    private func saveTrays(_ trays: [WorkTray], in settings: InMemorySettingRepository) async throws {
        let raw = String(data: try JSONEncoder().encode(trays), encoding: .utf8)!
        try await settings.set(raw, for: SettingKeys.workTrays)
    }

    @Test func tasksInTraysStayInResults_untilHidden() async throws {
        let repository = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let inTray = makeItem("In a tray")
        let pastDone = makeItem("Old finished task", status: .done)
        await repository.seed(inTray)
        await repository.seed(pastDone)
        let tray = WorkTray(name: "Now", itemIds: [inTray.id])
        try await saveTrays([tray], in: settings)

        let model = AllTasksViewModel(
            repository: repository,
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: settings
        )
        await model.load()

        #expect(model.hideTrayTasks == false)
        #expect(model.resultCount == 2)
        #expect(model.trayByItem[inTray.id]?.name == "Now")
        #expect(model.trayByItem[pastDone.id] == nil)

        model.hideTrayTasks = true
        #expect(model.resultCount == 1)
        #expect(model.hiddenTrayTaskCount == 1)
        #expect(model.groups.flatMap(\.results).map(\.id) == [pastDone.id])
        #expect(model.hasFilters)

        model.hideTrayTasks = false
        #expect(model.resultCount == 2)
        #expect(model.hiddenTrayTaskCount == 0)
    }

    @Test func reloadTrays_picksUpANewTrayDrop() async throws {
        let repository = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        let task = makeItem("Dragged later")
        await repository.seed(task)
        try await saveTrays([WorkTray(name: "Now")], in: settings)

        let model = AllTasksViewModel(
            repository: repository,
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: settings
        )
        await model.load()
        #expect(model.trayByItem.isEmpty)

        try await saveTrays([WorkTray(name: "Now", itemIds: [task.id])], in: settings)
        await model.reloadTrays()

        // The task is still listed, now with its tray.
        #expect(model.resultCount == 1)
        #expect(model.trayByItem[task.id]?.name == "Now")
    }

    @Test func hideChoice_isRestoredOnNextOpen() async throws {
        let repository = InMemoryWorkItemRepository()
        let settings = InMemorySettingRepository()
        try await settings.set("true", for: SettingKeys.allTasksHideTrayTasks)

        let model = AllTasksViewModel(
            repository: repository,
            attachmentRepository: InMemoryAttachmentRepository(),
            settingRepository: settings
        )
        await model.load()
        #expect(model.hideTrayTasks)
    }
}
