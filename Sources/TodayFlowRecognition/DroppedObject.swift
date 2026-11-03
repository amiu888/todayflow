import Foundation
import UniformTypeIdentifiers
import TodayFlowCore

/// A raw object dropped onto the app, before classification (driver.md §7 steps 1–2).
///
/// The app target (driver.md §11 increment 6) converts `NSItemProvider`s into
/// this type. Every field is optional because a single drop can be a file, a
/// folder, a URL, pasted text, or a pasted image — each recognizer looks only
/// at the fields it cares about.
///
/// `fileData` holds the bytes of small, transient files (`.eml`, `.msg`, `.ics`)
/// so recognizers stay pure: they parse in-memory data and are unit-tested with
/// fixtures (driver.md §7), with no disk access.
public struct DroppedObject: Hashable, Sendable {
    public var fileURL: URL?
    public var isDirectory: Bool?
    /// True when the file is a promise (e.g. Outlook's `.msg`) that only exists
    /// until the app copies it — the materializer must copy it into the container.
    public var isFilePromise: Bool?
    public var url: URL?
    public var text: String?
    public var imageData: Data?
    /// Contents of `fileURL` for small transient files, if the receive step loaded them.
    public var fileData: Data?
    /// Bundle identifier of the source app (e.g. `com.microsoft.outlook`), if known.
    public var sourceApp: String?
    public var uti: UTType?
    public var fileSize: Int64?
    public var modificationDate: Date?

    public init(
        fileURL: URL? = nil,
        isDirectory: Bool? = nil,
        isFilePromise: Bool? = nil,
        url: URL? = nil,
        text: String? = nil,
        imageData: Data? = nil,
        fileData: Data? = nil,
        sourceApp: String? = nil,
        uti: UTType? = nil,
        fileSize: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.fileURL = fileURL
        self.isDirectory = isDirectory
        self.isFilePromise = isFilePromise
        self.url = url
        self.text = text
        self.imageData = imageData
        self.fileData = fileData
        self.sourceApp = sourceApp
        self.uti = uti
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

/// A strategy that classifies one kind of dropped object (driver.md §7 step 3).
///
/// Recognizers are ordered in the pipeline; the first whose `canHandle` is true
/// wins. They must be pure and fast — the whole pipeline runs inside the 300 ms
/// drop-to-sheet budget (NFR-01).
public protocol ObjectRecognizer: Sendable {
    func canHandle(_ object: DroppedObject) -> Bool
    func recognize(_ object: DroppedObject) -> RecognizedObject
}
