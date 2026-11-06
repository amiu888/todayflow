import Foundation

/// The editable state of the quick-add capture sheet (driver.md §7 step 4).
///
/// Built synchronously from recognized objects the moment something is dropped,
/// so the sheet can open within the 300 ms budget (NFR-01). The user edits this
/// in the sheet; on save it becomes a `WorkItem` plus its `Attachment`s.
///
/// Holds `[RecognizedObject]`, not `[Attachment]`: the `WorkItem` id does not
/// exist until the draft is saved, and `Attachment` requires it.
public struct CaptureDraft: Hashable, Sendable, Codable {
    public var title: String
    public var descriptionMd: String
    public var startAt: Date
    public var endAt: Date
    public var priority: Priority
    public var parentId: UUIDv7?
    public var tags: [String]
    public var objects: [RecognizedObject]

    public init(
        title: String,
        descriptionMd: String = "",
        startAt: Date = .now,
        endAt: Date = .now,
        priority: Priority = .default,
        parentId: UUIDv7? = nil,
        tags: [String] = [],
        objects: [RecognizedObject] = []
    ) {
        self.title = title
        self.descriptionMd = descriptionMd
        self.startAt = startAt
        self.endAt = endAt
        self.priority = priority
        self.parentId = parentId
        self.tags = TagName.normalize(tags)
        self.objects = objects
    }

    /// The `Attachment` rows this draft will save, once `itemId` exists
    /// (driver.md §7 step 4: "one attachment per object").
    public func attachments(for itemId: UUIDv7, at date: Date = .now) -> [Attachment] {
        objects.map { $0.attachment(for: itemId, at: date) }
    }
}
