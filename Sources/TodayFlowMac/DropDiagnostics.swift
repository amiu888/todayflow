#if canImport(AppKit)
import Foundation

/// Local, privacy-safe drop diagnostics: type identifiers and counts only,
/// never file contents. Written to `~/Library/Logs/TodayFlow/drop.log` so a
/// failed drag can be diagnosed without reproducing it in a debugger.
@MainActor
enum DropDiagnostics {
    static var logURL: URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("TodayFlow", isDirectory: true)
            .appendingPathComponent("drop.log")
    }

    static func log(_ message: String) {
        let url = logURL
        let line = "[\(ISO8601DateFormatter().string(from: .now))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Diagnostics must never break a drop.
        }
    }
}
#endif
