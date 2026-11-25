import Foundation

/// One "Share → TodayFlow" item waiting for the iPhone app (docs/ios/DESIGN.md §4).
///
/// The share extension never opens the database: it writes `item.json` plus
/// any shared files into `<inbox>/<id>/`, and the app turns each folder into a
/// task through the same recognition pipeline as Mac drops.
public struct ShareInboxItem: Codable, Hashable, Sendable, Identifiable {
    public enum Due: String, Codable, Sendable, CaseIterable {
        /// The app's default schedule (today, due at end of business).
        case automatic
        case tomorrow
        case nextWeek
    }

    public var id: UUID
    public var createdAt: Date
    /// The title the person confirmed in the share sheet; empty = let the app pick.
    public var title: String
    public var priority: Priority
    public var due: Due
    public var urls: [URL]
    public var texts: [String]
    /// File names inside the item's folder.
    public var files: [String]
    /// The app the share came from, when known.
    public var sourceApp: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String = "",
        priority: Priority = .default,
        due: Due = .automatic,
        urls: [URL] = [],
        texts: [String] = [],
        files: [String] = [],
        sourceApp: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.priority = priority
        self.due = due
        self.urls = urls
        self.texts = texts
        self.files = files
        self.sourceApp = sourceApp
    }
}

/// The inbox folder shared by the app and its share extension.
public struct ShareInbox: Sendable {
    /// The app group shared by the iPhone app and its share extension.
    public static let appGroup = "group.com.todayflow.ios"

    public let directory: URL

    /// The inbox in the app group container, or nil when the group isn't
    /// available (an unsigned build).
    public static func shared() -> ShareInbox? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { ShareInbox(directory: $0.appendingPathComponent("Inbox", isDirectory: true)) }
    }

    public init(directory: URL) {
        self.directory = directory
    }

    public func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Writes the item last, so a half-written folder is never imported.
    public func add(_ item: ShareInboxItem, copying files: [URL] = []) throws -> ShareInboxItem {
        let manager = FileManager.default
        let folder = folder(for: item.id)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var item = item
        var used = Set(item.files)
        for source in files {
            let name = Self.uniqueName(source.lastPathComponent, used: &used)
            try manager.copyItem(at: source, to: folder.appendingPathComponent(name))
            item.files.append(name)
        }
        let data = try JSONEncoder().encode(item)
        try data.write(to: folder.appendingPathComponent(Self.itemFile), options: .atomic)
        return item
    }

    /// Complete items, oldest first. Folders without `item.json` are skipped.
    public func pending() -> [ShareInboxItem] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return folders
            .compactMap { folder -> ShareInboxItem? in
                guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.itemFile)) else { return nil }
                return try? JSONDecoder().decode(ShareInboxItem.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func fileURLs(for item: ShareInboxItem) -> [URL] {
        item.files.map { folder(for: item.id).appendingPathComponent($0) }
    }

    public func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }

    static let itemFile = "item.json"

    static func uniqueName(_ name: String, used: inout Set<String>) -> String {
        let clean = name.isEmpty ? "file" : name
        var candidate = clean
        var counter = 2
        let base = (clean as NSString).deletingPathExtension
        let ext = (clean as NSString).pathExtension
        while used.contains(candidate) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }
}
