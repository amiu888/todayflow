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
    /// Short plain-text description for the row's hover tooltip.
    public let descriptionPreview: String?
    public let priority: Priority
    public let isDone: Bool
    /// A prerequisite (`.blocks` link) is not yet complete — the row shows a lock.
    public let isBlocked: Bool
    public let dueAt: Date
    /// Optional effort estimate in minutes.
    public let estimatedMinutes: Int?
    public let isOverdue: Bool
    /// Due within 15 minutes: the row pulses and the panel shows a banner.
    public let isDueSoon: Bool
    public let completedAt: Date?
    /// Up to 3 attachment hints for the row's icon cluster.
    public let attachments: [AttachmentHint]
    /// Every attachment, for the hover overlay.
    public let allAttachments: [AttachmentHint]

    /// Working trays this task belongs to (for the tray badge and sorting).
    public struct TrayHint: Identifiable, Hashable, Sendable {
        public let id: UUIDv7
        public let name: String
        public let colorHex: String

        public init(id: UUIDv7, name: String, colorHex: String) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
        }
    }
    public let trays: [TrayHint]
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
        /// Bundle id of the app that supplied it (Finder, Outlook, Teams…).
        public let sourceApp: String?

        public init(
            kind: Attachment.Kind,
            displayName: String,
            sourceApp: String? = nil
        ) {
            self.kind = kind
            self.displayName = displayName
            self.sourceApp = sourceApp
        }
    }

    public init(
        id: UUIDv7,
        title: String,
        descriptionPreview: String? = nil,
        priority: Priority,
        isDone: Bool,
        isBlocked: Bool,
        dueAt: Date,
        estimatedMinutes: Int? = nil,
        isOverdue: Bool,
        isDueSoon: Bool = false,
        completedAt: Date? = nil,
        attachments: [AttachmentHint] = [],
        allAttachments: [AttachmentHint] = [],
        trays: [TrayHint] = [],
        attachmentCount: Int = 0,
        parentColorHex: String? = nil,
        hasChainBelow: Bool = false
    ) {
        self.id = id
        self.title = title
        self.descriptionPreview = descriptionPreview
        self.priority = priority
        self.isDone = isDone
        self.isBlocked = isBlocked
        self.dueAt = dueAt
        self.estimatedMinutes = estimatedMinutes
        self.isOverdue = isOverdue
        self.isDueSoon = isDueSoon
        self.completedAt = completedAt
        self.attachments = attachments
        self.allAttachments = allAttachments
        self.trays = trays
        self.attachmentCount = attachmentCount
        self.parentColorHex = parentColorHex
        self.hasChainBelow = hasChainBelow
    }
}
