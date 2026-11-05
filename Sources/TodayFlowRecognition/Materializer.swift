import Foundation
import TodayFlowCore

/// Copies transient dropped items into the app's `Attachments/` container and
/// stores security-scoped bookmarks for persistent files (driver.md §7 step 2).
///
/// The materializer must never throw and must stay fast — it runs inside the
/// 300 ms drop-to-sheet budget (NFR-01). When a copy or bookmark fails, the
/// object is returned unchanged: the reference to the original location is
/// still valid for the attachment's "reopen" behavior.
public struct Materializer: Sendable {
    public var fileAccess: any FileAccess
    public var attachmentsDirectory: URL

    public init(fileAccess: any FileAccess, attachmentsDirectory: URL) {
        self.fileAccess = fileAccess
        self.attachmentsDirectory = attachmentsDirectory
    }

    /// Returns the object with a local copy path or bookmark filled in where
    /// applicable. The input object is always returned (possibly unchanged).
    public func materialize(
        _ object: RecognizedObject,
        source: DroppedObject
    ) -> RecognizedObject {
        var result = object

        // Transient items must be copied into the container: file promises
        // (.msg, .eml, .ics from Outlook/Mail) disappear once the app leaves
        // the drop, and small message/event files are copied as well
        // (driver.md §7 step 2).
        if source.isFilePromise == true || Self.isTransientFile(source),
           let fileURL = source.fileURL
        {
            if let copyPath = copyIntoContainer(fileURL: fileURL, name: result.displayName) {
                result.localCopyPath = copyPath
                result.reference = copyPath
            }
            return result
        }

        // Pasted images: write the image data into the container.
        if object.type == .image, let data = source.imageData {
            let name = "\(result.displayName).png"
            if let copyPath = writeIntoContainer(data: data, name: name) {
                result.localCopyPath = copyPath
                result.reference = copyPath
            }
            return result
        }

        // Persistent files, folders, and image files: keep a security-scoped
        // bookmark so the attachment can reopen the original later, without a
        // copy. (Pasted image bytes took the branch above.)
        if (object.type == .file || object.type == .folder || object.type == .image),
           let fileURL = source.fileURL
        {
            if let bookmark = fileAccess.securityScopedBookmark(for: fileURL) {
                result.bookmark = bookmark
            }
        }

        return result
    }

    // MARK: - Container helpers

    /// `.eml`, `.msg`, and `.ics` files are treated as transient and copied
    /// into the container (driver.md §7 step 2).
    static func isTransientFile(_ source: DroppedObject) -> Bool {
        guard let ext = source.fileURL?.pathExtension.lowercased() else { return false }
        return ["eml", "msg", "ics"].contains(ext)
    }

    private func copyIntoContainer(fileURL: URL, name: String) -> String? {
        let destination = containerURL(named: sanitized(name))
        do {
            try fileAccess.createDirectory(attachmentsDirectory)
            try fileAccess.copy(from: fileURL, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    private func writeIntoContainer(data: Data, name: String) -> String? {
        let destination = containerURL(named: sanitized(name))
        do {
            try fileAccess.createDirectory(attachmentsDirectory)
            try fileAccess.write(data, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    private func containerURL(named name: String) -> URL {
        // A UUID prefix keeps same-named drops from colliding.
        attachmentsDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    private func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "[^A-Za-z0-9._ -]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "attachment" : cleaned
    }
}
