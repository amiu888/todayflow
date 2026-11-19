import Crypto
import Foundation
import NIOCore

/// Attachment files, stored on disk by the SHA-256 of their bytes, so the same
/// file is kept once no matter how many tasks or devices use it.
///
///     <root>/ab/abcdef…   (first two hex characters as a folder)
public struct BlobStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 64 lowercase hex characters.
    public static func isValidHash(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func url(for hash: String) -> URL {
        root.appendingPathComponent(String(hash.prefix(2)), isDirectory: true)
            .appendingPathComponent(hash)
    }

    public func exists(_ hash: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    public enum PutError: Error, Equatable {
        case hashMismatch(actual: String)
    }

    /// Stores `data` under `hash` after checking it. Returns false when it was
    /// already stored. Writes to a temporary file first, so a half-written file
    /// never appears under its final name.
    @discardableResult
    public func put(_ data: Data, hash: String) throws -> Bool {
        let actual = Self.sha256(data)
        guard actual == hash else { throw PutError.hashMismatch(actual: actual) }
        let target = url(for: hash)
        if FileManager.default.fileExists(atPath: target.path) { return false }
        let folder = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".\(hash).\(UUID().uuidString).tmp")
        try data.write(to: temporary)
        do {
            try FileManager.default.moveItem(at: temporary, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            // Another upload of the same file won the race: that is fine.
            if FileManager.default.fileExists(atPath: target.path) { return false }
            throw error
        }
        return true
    }

    public enum StreamError: Error, Equatable {
        case tooLarge
    }

    /// Stores a file as it arrives, hashing as it goes, so a large upload
    /// never has to fit in memory. Returns the size. Throws `tooLarge` past
    /// `maxBytes` and `hashMismatch` when the bytes aren't `hash`.
    public func put<Chunks: AsyncSequence>(
        streaming chunks: Chunks, hash: String, maxBytes: Int
    ) async throws -> Int where Chunks.Element == ByteBuffer {
        let target = url(for: hash)
        let folder = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".\(hash).\(UUID().uuidString).tmp")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        var hasher = SHA256()
        var size = 0
        do {
            for try await var chunk in chunks {
                size += chunk.readableBytes
                guard size <= maxBytes else { throw StreamError.tooLarge }
                let bytes = chunk.readBytes(length: chunk.readableBytes) ?? []
                hasher.update(data: bytes)
                try handle.write(contentsOf: bytes)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == hash else {
            try? FileManager.default.removeItem(at: temporary)
            throw PutError.hashMismatch(actual: actual)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: temporary)
            return size
        }
        do {
            try FileManager.default.moveItem(at: temporary, to: target)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if !FileManager.default.fileExists(atPath: target.path) { throw error }
        }
        return size
    }

    /// The stored file's location and size, for streaming it back.
    public func file(_ hash: String) -> (url: URL, size: Int)? {
        let target = url(for: hash)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? NSNumber
        else { return nil }
        return (target, size.intValue)
    }

    public func get(_ hash: String) throws -> Data? {
        let target = url(for: hash)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        return try Data(contentsOf: target)
    }

    /// Hashes of every stored file.
    public func allHashes() -> [String] {
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return folders.flatMap { folder -> [String] in
            let names = (try? FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent(folder).path
            )) ?? []
            return names.filter(Self.isValidHash)
        }
    }

    /// Deletes stored files nobody owns. Returns how many were removed.
    @discardableResult
    public func removeUnowned(keeping owned: Set<String>, minimumAge: TimeInterval = 3600) -> Int {
        var removed = 0
        let hourAgo = Date().addingTimeInterval(-minimumAge)
        for hash in allHashes() where !owned.contains(hash) {
            // A file uploaded a moment ago may not be claimed yet.
            let modified = (try? FileManager.default.attributesOfItem(atPath: url(for: hash).path))?[.modificationDate] as? Date
            if let modified, modified > hourAgo { continue }
            if (try? FileManager.default.removeItem(at: url(for: hash))) != nil { removed += 1 }
        }
        return removed
    }
}
