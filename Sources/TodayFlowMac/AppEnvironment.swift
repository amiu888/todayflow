import Foundation
import GRDB
import TodayFlowCore
import TodayFlowPersistence
import TodayFlowRecognition

/// The app's composition root (driver.md §11 build order 6, line 215): every
/// dependency is injected through the constructor — no hidden singletons, and
/// tests swap in in-memory doubles.
@MainActor
public final class AppEnvironment {
    public let workItems: any WorkItemRepository
    public let links: any LinkRepository
    public let attachments: any AttachmentRepository
    public let settings: any SettingRepository
    public let pipeline: RecognitionPipeline

    /// The user's working-hours model (driver.md line 49). Refreshed from the
    /// settings store by `loadSettings()`.
    public var workCalendar: WorkCalendar

    public init(
        workItems: any WorkItemRepository,
        links: any LinkRepository,
        attachments: any AttachmentRepository,
        settings: any SettingRepository,
        pipeline: RecognitionPipeline,
        workCalendar: WorkCalendar = .standard
    ) {
        self.workItems = workItems
        self.links = links
        self.attachments = attachments
        self.settings = settings
        self.pipeline = pipeline
        self.workCalendar = workCalendar
    }

    /// Production wiring: one SQLite file in Application Support
    /// (driver.md line 248: everything in one local SQLite database, GRDB, WAL).
    public static func makeProduction(databaseURL: URL? = nil) throws -> AppEnvironment {
        let url = databaseURL ?? defaultDatabaseURL()
        let queue = try TodayFlowDatabase.make(at: url)
        return AppEnvironment(
            workItems: GRDBWorkItemRepository(queue: queue),
            links: GRDBLinkRepository(queue: queue),
            attachments: GRDBAttachmentRepository(queue: queue),
            settings: GRDBSettingRepository(queue: queue),
            pipeline: .standard
        )
    }

    /// `~/Library/Application Support/TodayFlow/todayflow.sqlite`.
    public static func defaultDatabaseURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TodayFlow", isDirectory: true)
            .appendingPathComponent("todayflow.sqlite")
    }

    /// Loads the stored business-hours settings (driver.md line 49). A missing
    /// or corrupt value keeps the current calendar, mirroring
    /// `SettingsViewModel.load()`.
    public func loadSettings() async {
        guard
            let raw = await settings.value(for: SettingKeys.workCalendar),
            let data = raw.data(using: .utf8),
            let stored = try? JSONDecoder().decode(WorkCalendarSettings.self, from: data)
        else { return }
        workCalendar = stored.calendar
    }
}
