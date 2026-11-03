import Foundation

/// File-system operations the materializer needs (driver.md §7 step 2).
///
/// This is a port in the Clean Architecture sense: the materializer depends on
/// it, and tests substitute a fake to assert on copies and bookmarks without
/// touching the disk.
public protocol FileAccess: Sendable {
    func isDirectory(_ url: URL) -> Bool?
    func size(of url: URL) -> Int64?
    func modificationDate(of url: URL) -> Date?
    func copy(from source: URL, to destination: URL) throws
    func write(_ data: Data, to url: URL) throws
    /// A security-scoped bookmark for a persistent file or folder.
    func securityScopedBookmark(for url: URL) -> Data?
    func url(fromSecurityScopedBookmark data: Data) -> URL?
    func createDirectory(_ url: URL) throws
}

/// `FileManager`-backed `FileAccess`.
public struct FileManagerFileAccess: FileAccess {
    public init() {}

    public func isDirectory(_ url: URL) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue
    }

    public func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
    }

    public func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public func copy(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    public func securityScopedBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func url(fromSecurityScopedBookmark data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}
