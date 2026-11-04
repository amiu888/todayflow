import Foundation
import Observation
import TodayFlowCore

/// A node of the hierarchy tree (driver.md FR-16): a work item plus its
/// children and the progress rolled up from its subtree (driver.md §2).
public struct HierarchyNode: Identifiable, Hashable, Sendable {
    public var item: WorkItem
    public var children: [HierarchyNode]
    public var progress: RollUpProgress.Result

    public var id: UUIDv7 { item.id }

    public init(
        item: WorkItem,
        children: [HierarchyNode] = [],
        progress: RollUpProgress.Result
    ) {
        self.item = item
        self.children = children
        self.progress = progress
    }
}

/// One row of the flattened tree as rendered by `HierarchyView`: a node plus
/// its depth (the view indents by depth).
public struct VisibleRow: Identifiable, Hashable, Sendable {
    public let node: HierarchyNode
    public let depth: Int

    public var id: UUIDv7 { node.id }

    public init(node: HierarchyNode, depth: Int) {
        self.node = node
        self.depth = depth
    }
}

/// The hierarchy window's view model (driver.md FR-16, MVP gate line 515):
/// the full epics → projects → tasks → subtasks tree with per-node progress
/// roll-up, drag-to-reparent (kind-validated per driver.md §2), sibling
/// reordering (FR-12), and the §2 rule that deleting a parent unparents its
/// children.
///
/// All logic lives here; `HierarchyView` is pure presentation.
@MainActor
@Observable
public final class HierarchyViewModel {
    // MARK: - Dependencies

    @ObservationIgnored private let repository: any WorkItemRepository
    @ObservationIgnored private let linkRepository: any LinkRepository
    @ObservationIgnored private let calendar: WorkCalendar
    @ObservationIgnored private let deviceId: String
    @ObservationIgnored private let clock: @Sendable () -> Date

    /// Called when the user opens an item's detail (double-tap).
    @ObservationIgnored public var onOpenDetail: (@MainActor (UUIDv7) -> Void)?

    // MARK: - Observed state

    /// The tree's top-level nodes, in display order.
    public private(set) var nodes: [HierarchyNode] = []
    /// The ids of the expanded containers (a collapsed container hides its children).
    public private(set) var expanded: Set<UUIDv7> = []
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public private(set) var lastError: String?

    /// A plain item/children pair — the tree before progress is attached.
    private struct ItemNode {
        let item: WorkItem
        var children: [ItemNode]
    }

    @ObservationIgnored private var hasLoaded = false

    public init(
        repository: any WorkItemRepository,
        linkRepository: any LinkRepository,
        calendar: WorkCalendar = .standard,
        deviceId: String = "local",
        clock: @escaping @Sendable () -> Date = { .now }
    ) {
        self.repository = repository
        self.linkRepository = linkRepository
        self.calendar = calendar
        self.deviceId = deviceId
        self.clock = clock
    }

    // MARK: - Loading

    /// Rebuilds the tree from every live item, attaching rolled-up progress.
    ///
    /// The first successful load expands every container; later refreshes keep
    /// the user's expansion state.
    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let items = await repository.allItems()
        let tree = Self.itemTree(from: items)
        nodes = await Self.withProgress(tree, rollUp: RollUpProgress(repository: repository))

        if !hasLoaded {
            expanded = Self.containerIds(of: nodes)
            hasLoaded = true
        }
    }

    /// Builds the tree from the flat list of every live item.
    ///
    /// An item whose parent id does not appear in the list (a stale reference
    /// after a sync gap) floats to the top level instead of being silently
    /// dropped from the tree.
    private static func itemTree(from items: [WorkItem]) -> [ItemNode] {
        let present = Set(items.map(\.id))
        let reparented = items.map { item in
            guard let parentId = item.parentId, !present.contains(parentId) else {
                return item
            }
            var orphan = item
            orphan.parentId = nil
            return orphan
        }
        let byParent = Dictionary(grouping: reparented, by: \.parentId)
        func build(_ parentId: UUIDv7?) -> [ItemNode] {
            byParent[parentId, default: []]
                .sorted { FractionalIndex.isLessThan($0.displayOrder, $1.displayOrder) }
                .map { ItemNode(item: $0, children: build($0.id)) }
        }
        return build(nil)
    }

    /// Attaches rolled-up progress to every node — one `RollUpProgress.execute`
    /// per item, run concurrently.
    private static func withProgress(
        _ nodes: [ItemNode],
        rollUp: RollUpProgress
    ) async -> [HierarchyNode] {
        var items: [WorkItem] = []
        func flatten(_ node: ItemNode) {
            items.append(node.item)
            node.children.forEach(flatten)
        }
        nodes.forEach(flatten)

        let results = await withTaskGroup(of: (UUIDv7, RollUpProgress.Result).self) { group in
            for item in items {
                group.addTask {
                    (item.id, await rollUp.execute(item.id))
                }
            }
            var collected: [UUIDv7: RollUpProgress.Result] = [:]
            for await (id, result) in group {
                collected[id] = result
            }
            return collected
        }

        func build(_ node: ItemNode) -> HierarchyNode {
            HierarchyNode(
                item: node.item,
                children: node.children.map(build),
                progress: results[node.item.id]
                    ?? RollUpProgress.Result(done: 0, total: 0, fraction: 0)
            )
        }
        return nodes.map(build)
    }

    /// Every container id in the tree (the first load expands them all).
    private static func containerIds(of nodes: [HierarchyNode]) -> Set<UUIDv7> {
        var ids = Set<UUIDv7>()
        func walk(_ node: HierarchyNode) {
            if !node.children.isEmpty {
                ids.insert(node.id)
            }
            node.children.forEach(walk)
        }
        nodes.forEach(walk)
        return ids
    }

    // MARK: - Actions (driver.md §2 hierarchy rules)

    /// Adds a child of `kind` under `parentId` (FR-16). The kind must be
    /// allowed by the §2 table (epic → project, project → task, task → subtask);
    /// `CreateTask` enforces that and surfaces the error as `lastError`.
    @discardableResult
    public func addChild(
        to parentId: UUIDv7?,
        kind: WorkItem.Kind,
        title: String
    ) async -> WorkItem? {
        await withSaving {
            try await CreateTask(
                repository: self.repository,
                calendar: self.calendar,
                deviceId: self.deviceId
            ).execute(
                .init(
                    kind: kind,
                    title: title,
                    parentId: parentId,
                    startAt: self.clock()
                )
            )
        }
    }

    /// Re-parents `itemId` under `parentId` (FR-16 drag-and-drop).
    ///
    /// Validated per driver.md §2: the item cannot be its own parent and cannot
    /// be moved into its own descendant; the kind rule is enforced by
    /// `ReorderTask` (e.g. a task may only live under a project). The item is
    /// appended after the target's last child.
    public func reparent(_ itemId: UUIDv7, toParent parentId: UUIDv7) async {
        guard itemId != parentId else {
            lastError = "An item cannot be its own parent."
            return
        }
        guard !isDescendant(parentId, of: itemId) else {
            lastError = "An item cannot be moved into its own descendant."
            return
        }
        let siblings = await repository.children(of: parentId)
        let last = siblings.last { $0.id != itemId }
        await withSaving {
            try await ReorderTask(
                repository: self.repository,
                deviceId: self.deviceId
            ).execute(
                itemId,
                afterId: last?.id,
                newParentId: parentId,
                at: self.clock()
            )
        }
    }

    /// Moves `itemId` one position up among its siblings (FR-12 ⌥↑).
    public func moveUp(_ itemId: UUIDv7) async {
        guard
            let ids = siblingIds(of: itemId),
            let index = ids.firstIndex(of: itemId),
            index > 0
        else { return }
        // New slot: above = the item two places up (or the top), below = the
        // previous sibling. `ReorderTask` takes beforeId = upper bound (below
        // the new slot), afterId = lower bound (above it).
        await reorder(
            itemId,
            beforeId: ids[index - 1],
            afterId: index >= 2 ? ids[index - 2] : nil
        )
    }

    /// Moves `itemId` one position down among its siblings (FR-12 ⌥↓).
    public func moveDown(_ itemId: UUIDv7) async {
        guard
            let ids = siblingIds(of: itemId),
            let index = ids.firstIndex(of: itemId),
            index + 1 < ids.count
        else { return }
        await reorder(
            itemId,
            beforeId: index + 2 < ids.count ? ids[index + 2] : nil,
            afterId: ids[index + 1]
        )
    }

    /// Reorders `itemId` between two explicit sibling bounds: it ends up after
    /// `afterId` (lower bound) and before `beforeId` (upper bound); a nil bound
    /// is the end of the sibling list.
    private func reorder(
        _ itemId: UUIDv7,
        beforeId: UUIDv7?,
        afterId: UUIDv7?
    ) async {
        await withSaving {
            try await ReorderTask(
                repository: self.repository,
                deviceId: self.deviceId
            ).execute(
                itemId,
                beforeId: beforeId,
                afterId: afterId,
                at: self.clock()
            )
        }
    }

    /// Deletes `itemId`. By default the children survive, unparented
    /// (driver.md §2); `withChildren: true` takes the explicit "delete with
    /// children" option and removes the whole subtree.
    public func delete(_ itemId: UUIDv7, withChildren: Bool = false) async {
        await withSaving {
            try await DeleteTask(
                itemRepository: self.repository,
                linkRepository: self.linkRepository,
                deviceId: self.deviceId
            ).execute(itemId, withChildren: withChildren, at: self.clock())
        }
    }

    /// Marks `itemId` done, refreshing the rolled-up progress up the tree.
    public func complete(_ itemId: UUIDv7) async {
        await withSaving {
            try await CompleteTask(
                repository: self.repository,
                linkRepository: self.linkRepository,
                deviceId: self.deviceId
            ).execute(itemId, at: self.clock())
        }
    }

    /// Expands or collapses a container.
    public func toggle(_ id: UUIDv7) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    // MARK: - Tree queries

    /// The tree flattened into rendered rows (depth-first), honoring
    /// `expanded`: a collapsed container contributes only itself.
    public var visibleRows: [VisibleRow] {
        var rows: [VisibleRow] = []
        func walk(_ node: HierarchyNode, depth: Int) {
            rows.append(VisibleRow(node: node, depth: depth))
            guard expanded.contains(node.id) else { return }
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }
        for node in nodes {
            walk(node, depth: 0)
        }
        return rows
    }

    /// The ids of `itemId`'s siblings (including itself) in display order, or
    /// nil if the item is not in the current tree.
    private func siblingIds(of itemId: UUIDv7) -> [UUIDv7]? {
        if nodes.contains(where: { $0.id == itemId }) {
            return nodes.map(\.id)
        }
        func search(_ node: HierarchyNode) -> [UUIDv7]? {
            if node.children.contains(where: { $0.id == itemId }) {
                return node.children.map(\.id)
            }
            for child in node.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        for node in nodes {
            if let found = search(node) { return found }
        }
        return nil
    }

    /// Whether `candidateId` is `ancestorId` itself or anywhere below it.
    private func isDescendant(_ candidateId: UUIDv7, of ancestorId: UUIDv7) -> Bool {
        guard let ancestor = node(with: ancestorId) else { return false }
        func search(_ node: HierarchyNode) -> Bool {
            if node.id == candidateId { return true }
            return node.children.contains { search($0) }
        }
        return search(ancestor)
    }

    private func node(with id: UUIDv7) -> HierarchyNode? {
        func search(_ node: HierarchyNode) -> HierarchyNode? {
            if node.id == id { return node }
            for child in node.children {
                if let found = search(child) { return found }
            }
            return nil
        }
        for node in nodes {
            if let found = search(node) { return found }
        }
        return nil
    }

    // MARK: - Saving state

    /// Runs `operation` with the saving state, then refreshes the tree.
    /// Failures are surfaced as `lastError` (the view shows a dismissible
    /// note) rather than thrown — the tree is the source of truth.
    private func withSaving<R>(
        _ operation: () async throws -> R
    ) async -> R? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        lastError = nil
        do {
            let result = try await operation()
            await refresh()
            return result
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
