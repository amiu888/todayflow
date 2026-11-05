import Foundation

/// A dropped object after classification, before the capture sheet (driver.md §7 step 3).
///
/// This is the object the recognition pipeline produces and the capture sheet
/// displays. It carries everything the UI needs before a `WorkItem` exists: the
/// attachment kind, a display name, a suggested title, and a preview.
///
/// Lives in `TodayFlowCore` (Foundation only) because the `AIAssistant` port
/// (driver.md §8) references it, and Core must not depend on the recognition
/// package. The `ObjectRecognizer` protocol and the concrete recognizers live in
/// `TodayFlowRecognition`; they produce this type.
public struct RecognizedObject: Hashable, Sendable, Codable {
    public var type: Attachment.Kind
    public var uti: String?
    public var displayName: String
    public var sourceApp: String?
    public var reference: String?
    public var bookmark: Data?
    public var localCopyPath: String?
    public var metadata: [String: String]
    public var suggestedTitle: String?
    public var previewText: String?
    /// Populated for `.contact` drops so the capture flow can add the person
    /// to the contact list without re-parsing the vCard.
    public var contact: ImportedContact?

    public init(
        type: Attachment.Kind,
        uti: String? = nil,
        displayName: String,
        sourceApp: String? = nil,
        reference: String? = nil,
        bookmark: Data? = nil,
        localCopyPath: String? = nil,
        metadata: [String: String] = [:],
        suggestedTitle: String? = nil,
        previewText: String? = nil,
        contact: ImportedContact? = nil
    ) {
        self.type = type
        self.uti = uti
        self.displayName = displayName
        self.sourceApp = sourceApp
        self.reference = reference
        self.bookmark = bookmark
        self.localCopyPath = localCopyPath
        self.metadata = metadata
        self.suggestedTitle = suggestedTitle
        self.previewText = previewText
        self.contact = contact
    }

    /// Materializes the `Attachment` row this object will become once its
    /// `WorkItem` exists (driver.md §7 step 4 — the item id is not known until
    /// the draft is saved).
    public func attachment(for itemId: UUIDv7, at date: Date = .now) -> Attachment {
        Attachment(
            itemId: itemId,
            kind: type,
            uti: uti,
            displayName: displayName,
            sourceApp: sourceApp,
            reference: reference,
            bookmark: bookmark,
            localCopyPath: localCopyPath,
            metadata: metadata,
            previewText: previewText,
            createdAt: date
        )
    }
}
