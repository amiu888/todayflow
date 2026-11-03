import Foundation

/// Something captured alongside a work item when an object is dropped (driver.md §2, §7).
///
/// An attachment records *what* was dropped (a file, email, URL, image, …) and where
/// it came from, so the recognition pipeline can enrich the draft and the UI can show
/// a preview. The heavy bytes live on disk (or in the source app); only metadata is
/// persisted here.
public struct Attachment: Identifiable, Hashable, Sendable, Codable {
    /// What kind of object was dropped.
    public enum Kind: String, Codable, CaseIterable, Sendable, Hashable {
        case file
        case folder
        case email
        case calendarEvent
        case teamsMessage
        case url
        case image
        case text
    }

    public var id: UUIDv7
    /// The work item this attachment belongs to.
    public var itemId: UUIDv7
    public var kind: Kind
    /// Uniform Type Identifier (e.g. `com.adobe.pdf`), if known.
    public var uti: String?
    /// Human-friendly name (e.g. the file name, or the email subject).
    public var displayName: String
    /// Bundle identifier of the source app (e.g. `com.microsoft.outlook`), if known.
    public var sourceApp: String?
    /// Provider-specific reference: a file path, URL, or provider item id.
    public var reference: String?
    /// A security-scoped bookmark (macOS) so the file can be re-opened later.
    public var bookmark: Data?
    /// Where a local copy was materialized, if any.
    public var localCopyPath: String?
    /// Free-form metadata (page count, sender, size, …).
    public var metadata: [String: String]
    /// A short extracted preview (first lines of text, OCR, …).
    public var previewText: String?
    // Sync-ready conventions (driver.md §6).
    public var createdAt: Date
    public var version: Int
    public var deviceId: String

    public init(
        id: UUIDv7 = .new(),
        itemId: UUIDv7,
        kind: Kind,
        uti: String? = nil,
        displayName: String,
        sourceApp: String? = nil,
        reference: String? = nil,
        bookmark: Data? = nil,
        localCopyPath: String? = nil,
        metadata: [String: String] = [:],
        previewText: String? = nil,
        createdAt: Date = .now,
        version: Int = 1,
        deviceId: String = "local"
    ) {
        self.id = id
        self.itemId = itemId
        self.kind = kind
        self.uti = uti
        self.displayName = displayName
        self.sourceApp = sourceApp
        self.reference = reference
        self.bookmark = bookmark
        self.localCopyPath = localCopyPath
        self.metadata = metadata
        self.previewText = previewText
        self.createdAt = createdAt
        self.version = version
        self.deviceId = deviceId
    }
}
