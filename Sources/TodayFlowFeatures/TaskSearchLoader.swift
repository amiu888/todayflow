import Foundation
import TodayFlowCore

/// Loads every task with the text that lives in other tables (attachments,
/// checklist steps, linked contacts), for All Tasks and Quick Find.
enum TaskSearchLoader {
    static func load(
        repository: any WorkItemRepository,
        attachmentRepository: any AttachmentRepository,
        actionRepository: (any ActionItemRepository)?,
        contactRepository: (any ContactRepository)?
    ) async -> [TaskSearchRecord] {
        async let itemsTask = repository.allItems()
        async let attachmentsTask = attachmentRepository.allAttachments()
        async let actionsTask = actionRepository?.allActions() ?? []
        let (items, attachments, actions) = await (itemsTask, attachmentsTask, actionsTask)

        var contactNames: [UUIDv7: [String]] = [:]
        if let contactRepository {
            for contact in await contactRepository.contacts() {
                for taskId in await contactRepository.taskIds(forContact: contact.id) {
                    contactNames[taskId, default: []].append(contact.displayName)
                }
            }
        }

        let attachmentsByItem = Dictionary(grouping: attachments, by: \.itemId)
        let actionsByItem = Dictionary(grouping: actions, by: \.itemId)
        return items.map { item in
            TaskSearchRecord(
                item: item,
                attachments: attachmentsByItem[item.id] ?? [],
                actions: actionsByItem[item.id] ?? [],
                contactNames: contactNames[item.id] ?? []
            )
        }
    }
}
