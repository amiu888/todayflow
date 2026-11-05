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
    public let keychain: any KeychainStore
    public let pipeline: RecognitionPipeline
    /// Copies transient drops into the app container and bookmarks files
    /// (driver.md §7 step 2); the capture sheet uses it on save.
    public let materializer: Materializer

    /// The user's working-hours model (driver.md line 49). Refreshed from the
    /// settings store by `loadSettings()`.
    public var workCalendar: WorkCalendar

    /// Optional AI clients (driver.md §8); `nil` in tests/previews.
    public let ai: AIEnvironment?

    public init(
        workItems: any WorkItemRepository,
        links: any LinkRepository,
        attachments: any AttachmentRepository,
        settings: any SettingRepository,
        keychain: any KeychainStore,
        pipeline: RecognitionPipeline,
        materializer: Materializer = Materializer(
            fileAccess: FileManagerFileAccess(),
            attachmentsDirectory: AppEnvironment.defaultAttachmentsDirectory()
        ),
        workCalendar: WorkCalendar = .standard,
        ai: AIEnvironment? = nil
    ) {
        self.workItems = workItems
        self.links = links
        self.attachments = attachments
        self.settings = settings
        self.keychain = keychain
        self.pipeline = pipeline
        self.materializer = materializer
        self.workCalendar = workCalendar
        self.ai = ai
    }

    /// Production wiring: one SQLite file in Application Support
    /// (driver.md line 248: everything in one local SQLite database, GRDB, WAL).
    public static func makeProduction(databaseURL: URL? = nil) throws -> AppEnvironment {
        let url = databaseURL ?? defaultDatabaseURL()
        let queue = try TodayFlowDatabase.make(at: url)
        let settings = GRDBSettingRepository(queue: queue)
        let keychain = SecurityKeychainStore()
        return AppEnvironment(
            workItems: GRDBWorkItemRepository(queue: queue),
            links: GRDBLinkRepository(queue: queue),
            attachments: GRDBAttachmentRepository(queue: queue),
            settings: settings,
            keychain: keychain,
            pipeline: .standard,
            ai: AIEnvironment(settingsRepository: settings, keychain: keychain)
        )
    }

    /// `~/Library/Application Support/TodayFlow/todayflow.sqlite`.
    public static func defaultDatabaseURL() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("todayflow.sqlite")
    }

    /// `~/Library/Application Support/TodayFlow/Attachments` — where copies of
    /// transient drops (.eml/.msg/.ics and pasted images) live.
    public static func defaultAttachmentsDirectory() -> URL {
        applicationSupportDirectory()
            .appendingPathComponent("Attachments", isDirectory: true)
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TodayFlow", isDirectory: true)
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
