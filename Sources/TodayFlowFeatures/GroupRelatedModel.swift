import Foundation
import Observation
import TodayFlowCore
import TodayFlowDesign

/// "Group with related tasks": finds tasks that belong with one task and
/// puts the chosen ones in a project (a new one, or one that exists).
@MainActor
@Observable
public final class GroupRelatedModel {
    public enum Destination: Hashable {
        case newProject
        case existing(UUIDv7)
    }

    public let targetId: UUIDv7
    public private(set) var target: WorkItem?
    public private(set) var suggestions: [RelatedSuggestion] = []
    public private(set) var projects: [WorkItem] = []
    public var selected: Set<UUIDv7> = []
    public var destination: Destination = .newProject
    public var newProjectName = ""
    public private(set) var isLoading = true
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private var itemsById: [UUIDv7: WorkItem] = [:]
    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let attachmentRepository: any AttachmentRepository
    @ObservationIgnored private let actionRepository: (any ActionItemRepository)?
    @ObservationIgnored private let contactRepository: (any ContactRepository)?
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date

    @ObservationIgnored public var onDone: (@MainActor (String) -> Void)?
    @ObservationIgnored public var onCancel: (@MainActor () -> Void)?

    public init(
        targetId: UUIDv7,
        repository: any WorkItemRepository,
        attachmentRepository: any AttachmentRepository,
        actionRepository: (any ActionItemRepository)? = nil,
        contactRepository: (any ContactRepository)? = nil,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.targetId = targetId
        self.repository = repository
        self.attachmentRepository = attachmentRepository
        self.actionRepository = actionRepository
        self.contactRepository = contactRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        let records = await TaskSearchLoader.load(
            repository: repository,
            attachmentRepository: attachmentRepository,
            actionRepository: actionRepository,
            contactRepository: contactRepository
        )
        itemsById = Dictionary(records.map { ($0.item.id, $0.item) }, uniquingKeysWith: { first, _ in first })
        guard let targetRecord = records.first(where: { $0.item.id == targetId }) else { return }
        target = targetRecord.item
        projects = records.map(\.item)
            .filter { $0.kind == .project && !$0.isDeleted }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let currentProject = project(of: targetRecord.item)
        suggestions = RelatedTasks.suggest(for: targetRecord, among: records)
            // Already in the same project: nothing to do for those.
            .filter { currentProject == nil || project(of: $0.item)?.id != currentProject?.id }
        // Pre-select strong matches that are not filed somewhere else yet.
        selected = Set(suggestions.filter { $0.isStrong && project(of: $0.item) == nil }.map(\.id))

        if let currentProject {
            destination = .existing(currentProject.id)
        }
        let chosen = records.filter { selected.contains($0.item.id) }
        newProjectName = RelatedTasks.projectName(for: targetRecord, with: chosen)
    }

    /// The project a task is filed under (walking up through parents).
    public func project(of item: WorkItem) -> WorkItem? {
        var current = item.parentId.flatMap { itemsById[$0] }
        var hops = 0
        while let candidate = current, hops < 6 {
            if candidate.kind == .project { return candidate }
            current = candidate.parentId.flatMap { itemsById[$0] }
            hops += 1
        }
        return nil
    }

    public func toggle(_ id: UUIDv7) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Tasks that will move: the task itself plus the ticked ones.
    public var taskCount: Int { 1 + selected.count }

    public var applyTitle: String {
        switch destination {
        case .newProject: taskCount == 1 ? "Create Project" : "Group \(taskCount) Tasks"
        case .existing: taskCount == 1 ? "Move to Project" : "Move \(taskCount) Tasks"
        }
    }

    public var canApply: Bool {
        guard !isSaving, target != nil else { return false }
        if case .newProject = destination {
            return !newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    public func apply() async {
        guard canApply, let target else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let projectId: UUIDv7
            let projectTitle: String
            switch destination {
            case .existing(let id):
                projectId = id
                projectTitle = itemsById[id]?.title ?? "the project"
            case .newProject:
                let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                let project = try await CreateTask(repository: repository, calendar: calendar, deviceId: deviceId)
                    .execute(CreateTask.Input(
                        kind: .project, title: name, startAt: clock(),
                        color: DesignTokens.TrayPalette.colorHex(at: projects.count)
                    ))
                projectId = project.id
                projectTitle = name
            }
            let reorder = ReorderTask(repository: repository, deviceId: deviceId)
            // Subtasks stay under their task; only top-level work moves.
            let ids = [target.id] + suggestions.map(\.id).filter { selected.contains($0) }
            for id in ids where itemsById[id]?.kind != .subtask {
                try await reorder.execute(id, newParentId: projectId, at: clock())
            }
            let moved = ids.filter { itemsById[$0]?.kind != .subtask }.count
            onDone?(moved == 1 ? "Moved to \(projectTitle)" : "Grouped \(moved) tasks in \(projectTitle)")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
