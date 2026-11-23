import Foundation
import Testing
import TodayFlowCore
@testable import TodayFlowFeatures

@MainActor
struct GroupRelatedModelTests {
    private func make(_ items: [WorkItem], target: WorkItem) async -> (GroupRelatedModel, InMemoryWorkItemRepository) {
        let repository = InMemoryWorkItemRepository()
        for item in items { await repository.seed(item) }
        let model = GroupRelatedModel(
            targetId: target.id, repository: repository,
            attachmentRepository: InMemoryAttachmentRepository()
        )
        await model.load()
        return (model, repository)
    }

    @Test func suggestsSameTicketTasksAndNamesTheProjectAfterIt() async {
        let target = WorkItem(title: "CHG0012345 - remove Java")
        let rollback = WorkItem(title: "Rollback plan", descriptionMd: "for CHG0012345")
        let other = WorkItem(title: "Book dentist")
        let (model, _) = await make([target, rollback, other], target: target)

        #expect(model.suggestions.map(\.item.title) == ["Rollback plan"])
        #expect(model.selected == [rollback.id])
        #expect(model.newProjectName == "CHG0012345")
        #expect(model.applyTitle == "Group 2 Tasks")
    }

    @Test func applyCreatesTheProjectAndMovesTheTasks() async {
        let target = WorkItem(title: "CHG0012345 - remove Java")
        let rollback = WorkItem(title: "Rollback plan CHG0012345")
        let (model, repository) = await make([target, rollback], target: target)
        var message: String?
        model.onDone = { message = $0 }

        await model.apply()

        let project = await repository.allItems().first { $0.kind == .project }
        #expect(project?.title == "CHG0012345")
        #expect(await repository.item(target.id)?.parentId == project?.id)
        #expect(await repository.item(rollback.id)?.parentId == project?.id)
        #expect(message == "Grouped 2 tasks in CHG0012345")
    }

    @Test func aTaskAlreadyInAProjectDefaultsToThatProject() async {
        let project = WorkItem(kind: .project, title: "Server clean-up")
        let target = WorkItem(title: "CHG0012345 - remove Java", parentId: project.id)
        let loose = WorkItem(title: "Test CHG0012345")
        let (model, repository) = await make([project, target, loose], target: target)

        #expect(model.destination == .existing(project.id))
        #expect(model.applyTitle == "Move 2 Tasks")
        await model.apply()
        #expect(await repository.item(loose.id)?.parentId == project.id)
    }
}
