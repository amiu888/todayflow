#if os(iOS)
import Foundation
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowRecognition
import UniformTypeIdentifiers

/// Turns "Share → TodayFlow" items into tasks (docs/ios/DESIGN.md §4), through
/// the same recognition pipeline and capture rules as a Mac drop.
@MainActor
enum PhoneInboxImporter {
    /// The running import; launch and "came to the foreground" can both ask
    /// at once, and the second caller must wait instead of importing twice.
    private static var running: Task<[UUIDv7], Never>?

    /// Imports every complete inbox item; returns the new tasks' ids.
    @discardableResult
    static func importPending(_ environment: PhoneEnvironment, inbox: ShareInbox? = ShareInbox.shared()) async -> [UUIDv7] {
        if let running { return await running.value }
        let task = Task { await importAll(environment, inbox: inbox) }
        running = task
        defer { running = nil }
        return await task.value
    }

    private static func importAll(_ environment: PhoneEnvironment, inbox: ShareInbox?) async -> [UUIDv7] {
        guard let inbox else { return [] }
        var created: [UUIDv7] = []
        for item in inbox.pending() {
            if let id = await importItem(item, inbox: inbox, environment: environment) {
                created.append(id)
                inbox.remove(item.id)
            }
        }
        if !created.isEmpty {
            NotificationCenter.default.post(name: TodayFlowEvents.itemsChanged, object: nil)
        }
        return created
    }

    static func importItem(_ item: ShareInboxItem, inbox: ShareInbox, environment: PhoneEnvironment) async -> UUIDv7? {
        let dropped = droppedObjects(for: item, inbox: inbox)
        // Screenshots are read on the device; Apple Intelligence names the task.
        let reading = await PhoneSmartCapture.read(dropped, pipeline: environment.pipeline)
        let capture = CaptureViewModel(
            repository: environment.workItems,
            attachmentRepository: environment.attachments,
            contactRepository: environment.contacts,
            materializer: environment.materializer,
            calendar: environment.workCalendar
        )
        await PhoneSmartCapture.prepare(capture, dropped: dropped, reading: reading)
        if !item.title.isEmpty { capture.draft.title = item.title }
        if capture.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            capture.draft.title = "Shared item"
        }
        capture.draft.priority = item.priority
        if let day = day(for: item.due, calendar: environment.workCalendar) {
            let start = environment.workCalendar.startOfBusiness(for: day)
            capture.draft.startAt = start
            capture.draft.endAt = TaskSchedule.dueAfterStart(
                start: start, due: environment.workCalendar.endOfBusiness(for: day)
            )
        }
        await capture.save()
        guard capture.lastError == nil else { return nil }
        return capture.savedItem?.id
    }

    static func droppedObjects(for item: ShareInboxItem, inbox: ShareInbox) -> [DroppedObject] {
        var objects: [DroppedObject] = item.urls.map { DroppedObject(url: $0, sourceApp: item.sourceApp) }
        objects += item.texts.map { DroppedObject(text: $0, sourceApp: item.sourceApp) }
        for file in inbox.fileURLs(for: item) {
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber
            // The inbox folder is deleted after import, so every file is
            // treated like a Mac file promise: copied into Attachments.
            objects.append(DroppedObject(
                fileURL: file,
                isDirectory: false,
                isFilePromise: true,
                sourceApp: item.sourceApp,
                uti: UTType(filenameExtension: file.pathExtension),
                fileSize: size?.int64Value
            ))
        }
        return objects
    }

    static func day(for due: ShareInboxItem.Due, calendar: WorkCalendar) -> Date? {
        let today = calendar.calendar.startOfDay(for: .now)
        switch due {
        case .automatic: return nil
        case .tomorrow: return calendar.calendar.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: return calendar.calendar.date(byAdding: .day, value: 7, to: today)
        }
    }
}
#endif
