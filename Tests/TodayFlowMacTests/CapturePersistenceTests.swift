#if canImport(AppKit)
import Foundation
import GRDB
import Testing
import TodayFlowCore
import TodayFlowFeatures
import TodayFlowMac
import TodayFlowPersistence
import TodayFlowRecognition

/// End-to-end production-stack test: file-backed GRDB + real materializer +
/// the capture view model, proving a dropped PNG becomes a visible task.
@MainActor
struct CapturePersistenceTests {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    @Test func droppedPNG_becomesATaskAttachmentAndActivityEntry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodayFlowCaptureDB-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let image = root.appendingPathComponent("screen.png")
        try Self.png.write(to: image)
        let databaseURL = root.appendingPathComponent("todayflow.sqlite")
        let queue = try TodayFlowDatabase.make(at: databaseURL)
        defer { try? queue.close() }

        let items = GRDBWorkItemRepository(queue: queue, actor: "tester")
        let links = GRDBLinkRepository(queue: queue, actor: "tester")
        let attachments = GRDBAttachmentRepository(queue: queue)
        let activity = GRDBActivityRepository(queue: queue)
        let settings = GRDBSettingRepository(queue: queue)

        let dropped = DroppedObject(
            fileURL: image,
            isDirectory: false,
            sourceApp: "com.apple.finder",
            uti: .png,
            fileSize: Int64(Self.png.count)
        )
        let recognized = RecognitionPipeline.standard.recognize(dropped)
        #expect(recognized.type == .image)

        let model = CaptureViewModel(
            repository: items,
            attachmentRepository: attachments,
            materializer: Materializer(
                fileAccess: FileManagerFileAccess(),
                attachmentsDirectory: root.appendingPathComponent("Attachments", isDirectory: true)
            ),
            clock: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        model.prepare(dropped: [dropped], recognized: [recognized])
        model.draft.title = "Screenshot"
        await model.save()

        #expect(model.lastError == nil)
        let all = await items.allItems()
        #expect(all.count == 1)
        let saved = try #require(all.first)
        #expect(saved.title == "Screenshot")

        let savedAttachments = await attachments.attachments(for: saved.id)
        #expect(savedAttachments.count == 1)
        #expect(savedAttachments.first?.kind == .image)
        #expect(savedAttachments.first?.sourceApp == "com.apple.finder")

        let events = await activity.events(for: saved.id)
        #expect(events.contains { $0.kind == .created })
        #expect(events.contains {
            $0.kind == .dropped
                && $0.sourceApp == "com.apple.finder"
                && $0.location == image.path
        })

        // The Today list query sees the new task immediately.
        let today = await TodayQuery(
            repository: items,
            calendar: WorkCalendar(calendar: Calendar(identifier: .gregorian))
        ).execute(
            on: Date(timeIntervalSince1970: 1_800_000_000),
            at: Date(timeIntervalSince1970: 1_800_000_000)
        )
        #expect(today.all.contains { $0.id == saved.id })

        _ = links
        _ = settings
    }
}
#endif
