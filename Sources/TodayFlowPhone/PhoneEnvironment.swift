#if os(iOS)
import Foundation
import GRDB
import TodayFlowCore
import TodayFlowPersistence
import TodayFlowRecognition

/// The iPhone app's composition root: the same repositories as the Mac's
/// `AppEnvironment`, on the same GRDB schema, in the phone's own container.
@MainActor
public final class PhoneEnvironment {
    /// The app group shared with the share extension (docs/ios/DESIGN.md §4).
    public static let appGroup = ShareInbox.appGroup

    public let workItems: any WorkItemRepository
    public let links: any LinkRepository
    public let attachments: any AttachmentRepository
    public let contacts: any ContactRepository
    public let settings: any SettingRepository
    public let keychain: any KeychainStore
    public let reminders: any ReminderRepository
    public let actions: any ActionItemRepository
    public let activities: any ActivityRepository
    public let pipeline: RecognitionPipeline
    public let materializer: Materializer
    public var workCalendar: WorkCalendar
    public let databaseURL: URL?
    public let databaseQueue: DatabaseQueue?

    public init(
        workItems: any WorkItemRepository,
        links: any LinkRepository,
        attachments: any AttachmentRepository,
        contacts: any ContactRepository,
        settings: any SettingRepository,
        keychain: any KeychainStore,
        reminders: any ReminderRepository,
        actions: any ActionItemRepository,
        activities: any ActivityRepository,
        pipeline: RecognitionPipeline = .standard,
        materializer: Materializer,
        workCalendar: WorkCalendar = .standard,
        databaseURL: URL? = nil,
        databaseQueue: DatabaseQueue? = nil
    ) {
        self.workItems = workItems
        self.links = links
        self.attachments = attachments
        self.contacts = contacts
        self.settings = settings
        self.keychain = keychain
        self.reminders = reminders
        self.actions = actions
        self.activities = activities
        self.pipeline = pipeline
        self.materializer = materializer
        self.workCalendar = workCalendar
        self.databaseURL = databaseURL
        self.databaseQueue = databaseQueue
    }

    /// Production wiring: `Application Support/TodayFlow/todayflow.sqlite`.
    public static func makeProduction() throws -> PhoneEnvironment {
        let url = applicationSupportDirectory().appendingPathComponent("todayflow.sqlite")
        #if DEBUG
        // UI tests start from an empty database (then -seedSample fills it),
        // so one test's tasks and trays never change the next one's.
        if ProcessInfo.processInfo.arguments.contains("-resetData") {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        #endif
        let queue = try TodayFlowDatabase.make(at: url)
        return PhoneEnvironment(
            workItems: GRDBWorkItemRepository(queue: queue),
            links: GRDBLinkRepository(queue: queue),
            attachments: GRDBAttachmentRepository(queue: queue),
            contacts: GRDBContactRepository(queue: queue),
            settings: GRDBSettingRepository(queue: queue),
            keychain: SecurityKeychainStore(),
            reminders: GRDBReminderRepository(queue: queue),
            actions: GRDBActionItemRepository(queue: queue),
            activities: GRDBActivityRepository(queue: queue),
            materializer: Materializer(
                fileAccess: FileManagerFileAccess(),
                attachmentsDirectory: applicationSupportDirectory()
                    .appendingPathComponent("Attachments", isDirectory: true)
            ),
            databaseURL: url,
            databaseQueue: queue
        )
    }

    /// An in-memory environment for previews and when the database can't open.
    public static func makeInMemory() -> PhoneEnvironment {
        PhoneEnvironment(
            workItems: InMemoryWorkItemRepository(),
            links: InMemoryLinkRepository(),
            attachments: InMemoryAttachmentRepository(),
            contacts: InMemoryContactRepository(),
            settings: InMemorySettingRepository(),
            keychain: InMemoryKeychainStore(),
            reminders: InMemoryReminderRepository(),
            actions: InMemoryActionItemRepository(),
            activities: InMemoryActivityRepository(),
            materializer: Materializer(
                fileAccess: FileManagerFileAccess(),
                attachmentsDirectory: FileManager.default.temporaryDirectory
            )
        )
    }

    /// Reads the stored work-hours settings; a missing value keeps the default.
    public func loadSettings() async {
        guard
            let raw = await settings.value(for: SettingKeys.workCalendar),
            let data = raw.data(using: .utf8),
            let stored = try? JSONDecoder().decode(WorkCalendarSettings.self, from: data)
        else { return }
        workCalendar = stored.calendar
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("TodayFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
#endif
