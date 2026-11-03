import Foundation

/// Computes progress roll-up for a container work item (driver.md §2):
/// - a task / subtask (leaf) is 0 or 1 by its own status;
/// - a project's progress = done tasks / all tasks (its task children);
/// - an epic's progress = the task-count-weighted average of its projects, which
///   equals total done tasks / total tasks across its projects.
public struct RollUpProgress: Sendable {
    public struct Result {
        public var done: Int
        public var total: Int
        /// 0.0–1.0; 0 when there is nothing to roll up.
        public var fraction: Double

        public var isComplete: Bool { total > 0 && done == total }
    }

    private let repository: any WorkItemRepository

    public init(repository: any WorkItemRepository) {
        self.repository = repository
    }

    public func execute(_ id: UUIDv7) async -> Result {
        guard let item = await repository.item(id) else {
            return Result(done: 0, total: 0, fraction: 0)
        }
        switch item.kind {
        case .task, .subtask:
            let done = item.status.isComplete ? 1 : 0
            return Result(done: done, total: 1, fraction: Double(done))
        case .project:
            let tasks = await repository.children(of: id).filter { $0.kind == .task }
            let done = tasks.filter { $0.status.isComplete }.count
            let total = tasks.count
            return Result(done: done, total: total, fraction: total == 0 ? 0 : Double(done) / Double(total))
        case .epic:
            let projects = await repository.children(of: id).filter { $0.kind == .project }
            var done = 0
            var total = 0
            for project in projects {
                let tasks = await repository.children(of: project.id).filter { $0.kind == .task }
                done += tasks.filter { $0.status.isComplete }.count
                total += tasks.count
            }
            return Result(done: done, total: total, fraction: total == 0 ? 0 : Double(done) / Double(total))
        }
    }
}
