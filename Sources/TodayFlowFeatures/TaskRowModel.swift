import Foundation
import TodayFlowCore

/// Presentation model for one row in the Today list (driver.md §4 row spec).
///
/// A plain value type, decoupled from `WorkItem` so views (and their tests)
/// never touch the domain model. Built by `TodayViewModel` from
/// `TodayQuery.Result` plus link/attachment data.
public struct TaskRowModel: Identifiable, Hashable, Sendable {
    public let id: UUIDv7
    public let title: String
    public let priority: Priority
    public let isDone: Bool
    /// A prerequisite (`.blocks` link) is not yet complete — the row shows a lock.
    public let isBlocked: Bool
    public let dueAt: Date
    public let isOverdue: Bool
    /// Due within 15 minutes: the row pulses and the panel shows a banner.
    public let isDueSoon: Bool
    public let completedAt: Date?
    /// Up to 3 attachment hints for the row's icon cluster.
    public let attachments: [AttachmentHint]
    /// Total attachment count (drives the "+n" overflow).
    public let attachmentCount: Int
    /// Parent project/epic color strip hex; nil for root items.
    public let parentColorHex: String?
    /// A child row follows this row — draw the "┊" chain connector.
    public let hasChainBelow: Bool

    /// One icon slot: what was attached, and its display name.
    public struct AttachmentHint: Hashable, Sendable {
        public let kind: Attachment.Kind
        public let displayName: String

        public init(kind: Attachment.Kind, displayName: String) {
            self.kind = kind
            self.displayName = displayName
        }
    }

    public init(
        id: UUIDv7,
        title: String,
        priority: Priority,
        isDone: Bool,
        isBlocked: Bool,
        dueAt: Date,
        isOverdue: Bool,
        isDueSoon: Bool = false,
        completedAt: Date? = nil,
        attachments: [AttachmentHint] = [],
        attachmentCount: Int = 0,
        parentColorHex: String? = nil,
        hasChainBelow: Bool = false
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.isDone = isDone
        self.isBlocked = isBlocked
        self.dueAt = dueAt
        self.isOverdue = isOverdue
        self.isDueSoon = isDueSoon
        self.completedAt = completedAt
        self.attachments = attachments
        self.attachmentCount = attachmentCount
        self.parentColorHex = parentColorHex
        self.hasChainBelow = hasChainBelow
    }
}
