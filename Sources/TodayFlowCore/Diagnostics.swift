import Foundation

/// Minimal local diagnostics for paths that are hard to reproduce in tests.
///
/// Writes plain text to `~/Library/Logs/TodayFlow/app.log`. Foundation-only so
/// Core stays platform-rule compliant; messages must never include file
/// contents or credentials.
public enum Diagnostics {
    private static let lock = NSLock()

    public static var logURL: URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("TodayFlow", isDirectory: true)
            .appendingPathComponent("app.log")
    }

    public static func log(_ category: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        let url = logURL
        let line = "[\(ISO8601DateFormatter().string(from: .now))] [\(category)] \(message)\n"
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
            // Diagnostics never affect app behavior.
        }
    }
}
