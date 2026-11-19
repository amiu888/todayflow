import Foundation

/// The dumps the backup service writes, and the "back up now" request.
///
/// The server never runs `pg_dump` itself: it drops a request file into a
/// folder shared with the backup container, which sees it within seconds.
public struct BackupCatalog: Sendable {
    public let backups: URL
    public let control: URL

    public init(backups: URL, control: URL) {
        self.backups = backups
        self.control = control
    }

    public struct Dump: Sendable, Equatable {
        public var name: String
        public var size: Int64
        public var created: Date
    }

    /// `todayflow-20261119-104717.dump`
    public static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^todayflow-\d{8}-\d{6}\.dump$"#, options: .regularExpression) != nil
    }

    /// The time in the name (UTC), which survives copying the file.
    static func date(fromName name: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "'todayflow-'yyyyMMdd-HHmmss'.dump'"
        return formatter.date(from: name)
    }

    /// Newest first.
    public func dumps() -> [Dump] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []
        return names.filter(Self.isValidName).compactMap { name -> Dump? in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: backups.appendingPathComponent(name).path
            )
            guard let size = attributes?[.size] as? NSNumber,
                  let created = Self.date(fromName: name) ?? attributes?[.modificationDate] as? Date
            else { return nil }
            return Dump(name: name, size: size.int64Value, created: created)
        }
        .sorted { $0.name > $1.name }
    }

    public func url(of name: String) -> URL? {
        Self.isValidName(name) ? backups.appendingPathComponent(name) : nil
    }

    var requestFile: URL { control.appendingPathComponent("backup-now") }

    public func requestBackup() throws {
        try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
        try Data("requested\n".utf8).write(to: requestFile)
    }

    public var isBackupPending: Bool {
        FileManager.default.fileExists(atPath: requestFile.path)
    }
}
